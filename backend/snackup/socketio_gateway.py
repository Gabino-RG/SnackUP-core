"""Socket.IO V3 gateway, mounted separately from the legacy native WebSocket.

Connect with ``transports: ['websocket'], auth: {token: accessToken}``.
The ``subscribe``/``unsubscribe`` events accept ``{topics: [topic, ...]}`` and
acknowledge with ``{ok, topics}``. Credentials never belong in query strings.
Clients renew access via REST and reconnect; no in-place privilege changes.
"""
import asyncio
from contextlib import suppress
from dataclasses import dataclass, field
import logging
import time
from urllib.parse import parse_qs

import socketio
from sqlalchemy import select

from .auth import verify_access_token
from .errors import ApiError
from .operation_models import Business


@dataclass(frozen=True)
class Identity:
    user_id: str
    role: str
    business_id: str | None


@dataclass
class Connection:
    token: str
    identity: Identity
    topics: set[str] = field(default_factory=set)
    window: float = field(default_factory=time.monotonic)
    messages: int = 0


def _identity(db, token, settings):
    user = verify_access_token(token, db, settings)
    return Identity(user.id, user.role, user.business_id)


def _canonical_topic(topic):
    if topic.startswith("room_business_"):
        return "business:" + topic.removeprefix("room_business_") + ":orders"
    if topic.startswith("room_user_"):
        return "user:" + topic.removeprefix("room_user_") + ":orders"
    return topic


def sanitized_event(event):
    """A second boundary prevents future outbox changes leaking private fields."""
    kind, topic, data = event.get("type"), event.get("topic"), event.get("data")
    if not isinstance(data, dict) or not isinstance(topic, str):
        return None
    if kind in {"order.created", "order.updated"} and topic.endswith(":orders"):
        allowed = {"id", "businessId", "status", "version", "updatedAt", "isRated", "change"}
        if topic.startswith("user:") and kind != "order.updated":
            return None
    elif kind in {"order.pickup_soon", "order.business_closed"} and topic.endswith(":orders"):
        if kind == "order.pickup_soon" and not topic.startswith("business:"):
            return None
        if kind == "order.business_closed" and not topic.startswith("user:"):
            return None
        allowed = {"id", "businessId", "status", "version", "updatedAt", "scheduledPickupTime"}
    elif kind in {"chat.message", "chat.closed", "chat.opened"} and topic.endswith(":chats"):
        allowed = {"chatId", "messageId"}
    elif kind == "product.updated" and topic.startswith("business:") and topic.endswith(":products"):
        allowed = {"id", "businessId", "name", "description", "category", "price", "stock", "imageUrl",
                   "isAvailable", "isFeatured", "version", "updatedAt", "deletedAt"}
    elif kind == "business.updated" and topic.startswith("business:") and not topic.endswith((":orders", ":products")):
        allowed = {"id", "name", "description", "category", "isOpen", "isActive", "version", "updatedAt", "logoUrl"}
    else:
        return None
    return {"id": event.get("id"), "type": kind, "topic": topic,
            "occurredAt": event.get("occurredAt"),
            "data": {key: value for key, value in data.items() if key in allowed
                     and (value is None or isinstance(value, (str, int, float, bool)))}}


class SocketIOGateway:
    def __init__(self, app):
        self.app, self.settings, self.db, self.bridge = app, app.state.settings, app.state.db, app.state.events
        protocol_log = logging.Logger("snackup.socketio.protocol")
        # Engine.IO debug messages can contain entire authentication packets.
        # Do not let a deployment-wide logging level expose access tokens.
        protocol_log.disabled = True
        self.sio = socketio.AsyncServer(async_mode="asgi", transports=["websocket"], allow_upgrades=False,
            cors_allowed_origins=[self.settings.public_origin], cors_credentials=False,
            max_http_buffer_size=16384, logger=protocol_log, engineio_logger=protocol_log, async_handlers=False,
            ping_interval=25, ping_timeout=20)
        self.connections: dict[str, Connection] = {}
        self.queue = asyncio.Queue(maxsize=200)
        self.tasks = []
        self.overflow = False
        self.handshake_timeout_seconds = 10
        self.sio.on("connect", self._connect)
        self.sio.on("disconnect", self._disconnect)
        self.sio.on("subscribe", self._subscribe)
        self.sio.on("unsubscribe", self._unsubscribe)
        self.sio.on("*", self._unsupported)
        self.asgi = socketio.ASGIApp(self.sio, socketio_path=None)
        self.bridge.add_listener(self._enqueue)

    def _validate(self, token, expected=None, topics=()):
        with self.db.sessions() as db:
            identity = _identity(db, token, self.settings)
            if expected is not None and identity != expected:
                raise ApiError(401, "UNAUTHENTICATED")
            public_businesses = set()
            for topic in topics:
                if topic.endswith(":chats"):
                    if identity.role == "user" and topic == f"user:{identity.user_id}:chats":
                        continue
                    if identity.role == "business" and topic == f"business:{identity.business_id}:chats":
                        continue
                    raise ApiError(403, "FORBIDDEN")
                if topic.endswith(":orders"):
                    if identity.role == "user" and topic == f"user:{identity.user_id}:orders":
                        continue
                    if identity.role == "business" and topic == f"business:{identity.business_id}:orders":
                        continue
                    raise ApiError(403, "FORBIDDEN")
                if not topic.startswith("business:"):
                    raise ApiError(403, "FORBIDDEN")
                business = topic.removeprefix("business:")
                if business.endswith(":products"):
                    business = business.removesuffix(":products")
                if not business:
                    raise ApiError(403, "FORBIDDEN")
                if identity.role == "business" and business != identity.business_id:
                    raise ApiError(403, "FORBIDDEN")
                public_businesses.add(business)
            if public_businesses:
                active = set(db.scalars(select(Business.id).where(Business.id.in_(public_businesses),
                                                                 Business.is_active.is_(True))))
                if active != public_businesses:
                    raise ApiError(403, "FORBIDDEN")
            return identity

    async def _connect(self, sid, environ, auth):
        if not isinstance(auth, dict) or set(auth) != {"token"} or not isinstance(auth["token"], str) or len(auth["token"]) > 8192:
            raise socketio.exceptions.ConnectionRefusedError("UNAUTHENTICATED", {"code": "UNAUTHENTICATED"})
        scope = environ.get("asgi.scope", {})
        remaining = max(0, scope.get("snackup.auth_deadline", time.monotonic() + self.handshake_timeout_seconds) - time.monotonic())
        try:
            identity = await asyncio.wait_for(asyncio.to_thread(self._validate, auth["token"]), timeout=remaining)
        except ApiError as error:
            raise socketio.exceptions.ConnectionRefusedError(error.code, {"code": error.code}) from None
        except Exception:
            raise socketio.exceptions.ConnectionRefusedError("AUTH_UNAVAILABLE", {"code": "AUTH_UNAVAILABLE"}) from None
        self.connections[sid] = Connection(auth["token"], identity)
        if scope.get("snackup.authenticated") is not None:
            scope["snackup.authenticated"].set()
        await self.start()
        # Clients explicitly subscribe and reconcile REST after acknowledgment.
        return True

    async def _disconnect(self, sid, reason=None):
        self.connections.pop(sid, None)

    async def _close(self, sid):
        eio_sid = self.sio.manager.eio_sid_from_sid(sid, "/")
        with suppress(Exception):
            await self.sio.disconnect(sid)
        if eio_sid is not None:
            with suppress(Exception):
                # A disconnected ASGI peer can leave Engine.IO's writer gone
                # before its queue drains; never hang shutdown on queue.join().
                await asyncio.wait_for(self.sio.eio.disconnect(eio_sid), timeout=1)
        self.connections.pop(sid, None)

    async def _request(self, sid, payload, subscribe):
        connection = self.connections.get(sid)
        if connection is None:
            return {"ok": False, "error": {"code": "UNAUTHENTICATED"}}
        if time.monotonic() - connection.window >= 60:
            connection.window, connection.messages = time.monotonic(), 0
        connection.messages += 1
        if connection.messages > 120:
            await self._close(sid)
            return {"ok": False, "error": {"code": "RATE_LIMITED"}}
        if (not isinstance(payload, dict) or set(payload) != {"topics"} or not isinstance(payload["topics"], list)
                or not 1 <= len(payload["topics"]) <= 64
                or any(not isinstance(topic, str) or not 1 <= len(topic) <= 1600 for topic in payload["topics"])):
            return {"ok": False, "error": {"code": "INVALID_INPUT"}}
        topics = {_canonical_topic(topic) for topic in payload["topics"]}
        if subscribe and len(connection.topics | topics) > 64:
            return {"ok": False, "error": {"code": "SUBSCRIPTION_LIMIT"}}
        try:
            await asyncio.to_thread(self._validate, connection.token, connection.identity, topics)
        except ApiError as error:
            if error.code != "FORBIDDEN":
                await self._close(sid)
            return {"ok": False, "error": {"code": error.code}}
        except Exception:
            await self._close(sid)
            return {"ok": False, "error": {"code": "AUTH_UNAVAILABLE"}}
        for topic in topics:
            if subscribe:
                connection.topics.add(topic)
                await self.sio.enter_room(sid, topic)
            else:
                connection.topics.discard(topic)
                await self.sio.leave_room(sid, topic)
        return {"ok": True, "topics": sorted(connection.topics)}

    async def _subscribe(self, sid, payload=None):
        return await self._request(sid, payload, True)

    async def _unsubscribe(self, sid, payload=None):
        return await self._request(sid, payload, False)

    async def _unsupported(self, event, sid, *args):
        connection = self.connections.get(sid)
        if connection:
            if time.monotonic() - connection.window >= 60:
                connection.window, connection.messages = time.monotonic(), 0
            connection.messages += 1
            if connection.messages > 120:
                await self._close(sid)
        return {"ok": False, "error": {"code": "INVALID_EVENT"}}

    def _enqueue(self, event):
        try:
            self.queue.put_nowait(event)
        except asyncio.QueueFull:
            # Bounded memory; force clients to reconcile after reconnecting.
            self.overflow = True

    async def emit_event(self, event):
        event = sanitized_event(event)
        if event is None:
            return
        for sid, connection in list(self.connections.items()):
            if event["topic"] not in connection.topics:
                continue
            try:
                await asyncio.to_thread(self._validate, connection.token, connection.identity, [event["topic"]])
            except Exception:
                await self._close(sid)
                continue
            if self.connections.get(sid) is connection:
                # Per-recipient checks are deliberate: a broad room/Redis emit
                # could send to a session revoked after it joined the room.
                delivery = event
                if event["type"] == "chat.message":
                    try:
                        delivery = await asyncio.to_thread(self._chat_message, connection, event)
                    except Exception:
                        await self._close(sid)
                        continue
                if delivery is not None:
                    await self.sio.emit(event["type"], delivery, to=sid)

    def _chat_message(self, connection, event):
        from .v32_chat import realtime_message
        with self.db.sessions() as db:
            identity = _identity(db, connection.token, self.settings)
            if identity != connection.identity:
                return None
            return realtime_message(db, identity, event)

    async def _event_loop(self):
        while True:
            event = await self.queue.get()
            if self.overflow:
                self.overflow = False
                await asyncio.gather(*(self._close(sid) for sid in list(self.connections)))
            await self.emit_event(event)

    async def _check_connection(self, sid, connection):
        try:
            await asyncio.to_thread(self._validate, connection.token, connection.identity)
        except Exception:
            await self._close(sid)

    async def _revalidate_loop(self):
        while True:
            await asyncio.sleep(self.settings.websocket_revalidate_seconds)
            await asyncio.gather(*(self._check_connection(sid, connection)
                                  for sid, connection in list(self.connections.items())))

    async def start(self):
        if not self.tasks:
            self.tasks = [asyncio.create_task(self._event_loop()), asyncio.create_task(self._revalidate_loop())]

    async def stop(self):
        for task in self.tasks:
            task.cancel()
        await asyncio.gather(*self.tasks, return_exceptions=True)
        self.tasks = []
        await asyncio.gather(*(self._close(sid) for sid in list(self.connections)))
        self.bridge.remove_listener(self._enqueue)
        with suppress(asyncio.TimeoutError):
            await asyncio.wait_for(self.sio.shutdown(), timeout=2)

    async def __call__(self, scope, receive, send):
        if scope["type"] not in {"http", "websocket"}:
            await self.asgi(scope, receive, send)
            return
        try:
            raw_query = scope.get("query_string", b"")
            if len(raw_query) > 1024:
                raise ValueError
            query = parse_qs(raw_query.decode("ascii"), keep_blank_values=True)
            headers = {key.lower(): value for key, value in scope.get("headers", [])}
            origin = headers.get(b"origin")
            if (set(query) - {"EIO", "transport", "sid", "t", "b64"}
                    or query.get("transport") != ["websocket"] or query.get("EIO") != ["4"]
                    or (origin is not None and origin.decode("ascii") != self.settings.public_origin)):
                raise ValueError
            if scope["type"] != "websocket" or self.bridge.connections >= self.settings.max_websockets:
                raise ValueError
        except (ValueError, UnicodeError):
            if scope["type"] == "websocket":
                await send({"type": "websocket.close", "code": 1008})
            else:
                await send({"type": "http.response.start", "status": 400,
                            "headers": [(b"content-type", b"application/json"), (b"cache-control", b"no-store")]})
                await send({"type": "http.response.body", "body": b'{"error":{"code":"WEBSOCKET_REQUIRED"}}'})
            return
        # Reservations include physical connections awaiting the auth packet.
        self.bridge.connections += 1
        scope = dict(scope)
        authenticated = scope["snackup.authenticated"] = asyncio.Event()
        deadline = scope["snackup.auth_deadline"] = time.monotonic() + self.handshake_timeout_seconds

        async def receive_with_auth_deadline():
            # This is one overall deadline, so unauthenticated ping/pong traffic
            # cannot keep a physical connection and consume capacity forever.
            if authenticated.is_set():
                return await receive()
            try:
                return await asyncio.wait_for(receive(), timeout=max(0, deadline - time.monotonic()))
            except asyncio.TimeoutError:
                with suppress(Exception):
                    await send({"type": "websocket.close", "code": 1008})
                return {"type": "websocket.disconnect", "code": 1008}

        try:
            await self.asgi(scope, receive_with_auth_deadline, send)
        finally:
            self.bridge.connections -= 1


def install_socketio(app):
    gateway = SocketIOGateway(app)
    app.state.socketio_gateway = gateway
    app.mount("/socket.io", gateway, name="socketio")
    return gateway
