"""Commit-first SQL outbox and Redis fan-out for both realtime protocols.

Pub/sub is an online notification channel. REST remains authoritative and the
existing frontend periodically reconciles its state after missing notifications.
"""
import asyncio
from contextlib import suppress
from datetime import timedelta
import json
import logging
import time

from fastapi import APIRouter, Request, WebSocket, WebSocketDisconnect
from redis import Redis
from redis.asyncio import Redis as AsyncRedis
from sqlalchemy import or_, select

from .db import OutboxEvent, utcnow
from .errors import ApiError

router = APIRouter()
log = logging.getLogger('snackup.events')
CHANNEL = 'snackup:events:v1'


class EventBridge:
    def __init__(self, database, settings):
        self.db = database
        self.settings = settings
        self.clients = {}  # queue -> allowed topics
        self.connections = 0  # Both protocols, including unauthenticated handshakes.
        self.tasks = []
        self.listeners = set()
        self.dispatch_paused_until = 0
        self.subscription_ready = asyncio.Event()
        self.redis = Redis.from_url(settings.redis_url, socket_timeout=2, socket_connect_timeout=2) if settings.redis_url else None
        self.subscriber = None

    def add_listener(self, listener):
        self.listeners.add(listener)

    def remove_listener(self, listener):
        self.listeners.discard(listener)

    def broadcast(self, event):
        for listener in tuple(self.listeners):
            listener(event)
        for queue, topics in list(self.clients.items()):
            if event.get('topic') in topics:
                try:
                    queue.put_nowait(event)
                except asyncio.QueueFull:
                    # Force reconnect/reconciliation instead of growing memory.
                    with suppress(asyncio.QueueEmpty):
                        queue.get_nowait()
                    with suppress(asyncio.QueueFull):
                        queue.put_nowait({'type': 'error', 'code': 'SLOW_CONSUMER'})

    def _dispatch(self):
        from .push import enqueue_outbox_push
        from .auth import as_utc
        if self.redis and time.monotonic() < self.dispatch_paused_until:
            return []
        local = []
        failure = None
        with self.db.sessions.begin() as db:
            query = select(OutboxEvent).where(OutboxEvent.published_at.is_(None))
            if self.redis:
                query = query.where(or_(OutboxEvent.next_attempt_at.is_(None), OutboxEvent.next_attempt_at <= utcnow()))
            rows = db.scalars(query.order_by(OutboxEvent.id).limit(100).with_for_update(skip_locked=True)).all()
            for row in rows:
                # Push jobs and publication state commit together; publication
                # retries cannot enqueue the same event/device twice.
                enqueue_outbox_push(db, row)
                event = {'id': row.event_id, 'type': row.event_type, 'topic': row.topic,
                         'occurredAt': as_utc(row.created_at).isoformat(), 'data': row.data}
                row.publish_attempts += 1
                try:
                    if self.redis:
                        self.redis.publish(CHANNEL, json.dumps(event))
                    else:
                        local.append(event)
                    row.published_at, row.last_error, row.next_attempt_at = utcnow(), None, None
                except Exception as error:
                    delay = min(60, 2 ** min(row.publish_attempts, 6))
                    row.last_error, row.next_attempt_at = 'REDIS_PUBLISH_FAILED', utcnow() + timedelta(seconds=delay)
                    self.dispatch_paused_until = time.monotonic() + delay
                    failure = error
                    # Persist the failed attempt and any jobs already enqueued.
                    # Do not hammer the remaining rows during a broker outage.
                    break
        if failure is not None:
            raise failure
        return local

    async def dispatch_once(self):
        for event in await asyncio.to_thread(self._dispatch):
            self.broadcast(event)

    async def publish_loop(self):
        while True:
            try:
                await self.dispatch_once()
            except asyncio.CancelledError:
                raise
            except Exception:
                # Failed Redis publish leaves outbox transaction pending for retry.
                log.warning('Event dispatch unavailable; pending records retained')
            await asyncio.sleep(0.25)

    async def subscribe_loop(self):
        self.subscriber = AsyncRedis.from_url(self.settings.redis_url, socket_timeout=None, socket_connect_timeout=2, health_check_interval=30)
        while True:
            try:
                async with self.subscriber.pubsub() as sub:
                    await sub.subscribe(CHANNEL)
                    async for item in sub.listen():
                        if item['type'] == 'subscribe':
                            self.subscription_ready.set()
                        elif item['type'] == 'message':
                            self.broadcast(json.loads(item['data']))
            except asyncio.CancelledError:
                raise
            except Exception:
                self.subscription_ready.clear()
                self.broadcast({'type': 'resync.required'})
                for queue in list(self.clients):
                    with suppress(asyncio.QueueFull):
                        queue.put_nowait({'type': 'error', 'code': 'RESYNC_REQUIRED'})
                log.warning('Event subscription unavailable; reconnecting')
                await asyncio.sleep(1)

    async def start(self):
        if self.tasks:
            return
        if self.redis:
            await asyncio.to_thread(self.redis.ping)
            self.subscription_ready.clear()
            self.tasks.append(asyncio.create_task(self.subscribe_loop()))
            # The worker must subscribe before it can publish its own outbox.
            # Waiting for the Redis acknowledgment avoids a startup race.
            await asyncio.wait_for(self.subscription_ready.wait(), timeout=5)
        self.tasks.append(asyncio.create_task(self.publish_loop()))

    async def stop(self):
        for task in self.tasks:
            task.cancel()
        await asyncio.gather(*self.tasks, return_exceptions=True)
        self.tasks = []
        if self.subscriber:
            await self.subscriber.aclose()
        if self.redis:
            self.redis.close()


def socket_identity(app, token):
    from .auth import verify_access_token
    with app.state.db.sessions() as db:
        user = verify_access_token(token, db, app.state.settings)
        if user.role == 'business' and user.business_id:
            return {f'business:{user.business_id}:orders', f'business:{user.business_id}'}
        if user.role == 'user':
            return {f'user:{user.id}:orders'}
        raise ApiError(403, 'FORBIDDEN', 'El perfil no puede suscribirse a estos eventos.')


@router.get('/realtime')
def require_websocket(request: Request):
    raise ApiError(426, 'UPGRADE_REQUIRED', 'Utiliza una conexión WebSocket.')


@router.websocket('/realtime')
async def realtime(websocket: WebSocket):
    app = websocket.app
    settings = app.state.settings
    bridge = app.state.events
    if websocket.headers.get('origin') != settings.public_origin or bridge.connections >= settings.max_websockets:
        await websocket.close(code=1008)
        return
    # Authentication is a message, never a credential in the URL.
    if websocket.query_params:
        await websocket.close(code=1008)
        return
    # No await between checking capacity and reserving it on this worker's loop.
    # A pending authentication consumes capacity too; finally always releases it.
    bridge.connections += 1
    queue = asyncio.Queue(maxsize=100)
    token = None
    allowed = set()
    incoming = outgoing = None
    last_validation = time.monotonic()
    authenticated_at = None
    try:
        await websocket.accept()
        first = await asyncio.wait_for(websocket.receive_text(), timeout=10)
        if len(first) > 4096:
            raise ApiError(400, 'INVALID_INPUT')
        message = json.loads(first)
        if message.get('action') != 'auth' or not isinstance(message.get('token'), str):
            raise ApiError(401, 'UNAUTHENTICATED')
        token = message['token']
        allowed = await asyncio.to_thread(socket_identity, app, token)
        authenticated_at = time.monotonic()
        bridge.clients[queue] = set()
        incoming = asyncio.create_task(websocket.receive_text())
        outgoing = asyncio.create_task(queue.get())
        messages = 0
        window = time.monotonic()
        while True:
            done, _ = await asyncio.wait({incoming, outgoing}, timeout=settings.websocket_revalidate_seconds,
                                         return_when=asyncio.FIRST_COMPLETED)
            now = time.monotonic()
            if now - last_validation >= settings.websocket_revalidate_seconds:
                refreshed = await asyncio.to_thread(socket_identity, app, token)
                if refreshed != allowed or now - authenticated_at > 90:
                    raise ApiError(401, 'UNAUTHENTICATED')
                last_validation = now
                await websocket.send_json({'type': 'ping'})
            if incoming in done:
                raw = incoming.result()
                incoming = asyncio.create_task(websocket.receive_text())
                if now - window >= 60:
                    messages, window = 0, now
                messages += 1
                if messages > 120 or len(raw) > 4096:
                    raise ApiError(429, 'RATE_LIMITED')
                message = json.loads(raw)
                if message.get('action') == 'auth':
                    new_token = message.get('token')
                    if not isinstance(new_token, str):
                        raise ApiError(401, 'UNAUTHENTICATED')
                    refreshed = await asyncio.to_thread(socket_identity, app, new_token)
                    if refreshed != allowed:
                        raise ApiError(401, 'UNAUTHENTICATED')
                    token = new_token
                    authenticated_at = last_validation = now
                elif message.get('action') == 'subscribe':
                    topics = message.get('topics')
                    if not isinstance(topics, list) or not topics or len(topics) > 2 or any(not isinstance(t, str) or t not in allowed for t in topics):
                        raise ApiError(403, 'FORBIDDEN')
                    bridge.clients[queue] = set(topics)
                    await websocket.send_json({'type': 'subscribed', 'topics': topics})
                elif message.get('action') != 'pong':
                    raise ApiError(400, 'INVALID_INPUT')
            if outgoing in done:
                event = outgoing.result()
                outgoing = asyncio.create_task(queue.get())
                # Revalidate on every notification, including revoked assignments.
                if await asyncio.to_thread(socket_identity, app, token) != allowed:
                    raise ApiError(401, 'UNAUTHENTICATED')
                await websocket.send_json(event)
                if event.get('type') == 'error':
                    await websocket.close(code=1008)
                    break
    except WebSocketDisconnect:
        pass
    except (ApiError, ValueError, TypeError, KeyError, asyncio.TimeoutError, AttributeError):
        with suppress(Exception):
            await websocket.send_json({'type': 'unauthorized'})
            await websocket.close(code=1008)
    finally:
        bridge.connections -= 1
        bridge.clients.pop(queue, None)
        for task in [incoming, outgoing]:
            if task:
                task.cancel()
        await asyncio.gather(*[t for t in [incoming, outgoing] if t], return_exceptions=True)
