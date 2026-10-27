"""Regressions for measured Phase A failures; no production traffic."""
import asyncio
from datetime import timedelta
import os

import pytest
from fastapi import Depends
from sqlalchemy import event, select
from sqlalchemy.exc import TimeoutError as PoolTimeoutError

from snackup import auth
from snackup.db import OutboxEvent, get_db, utcnow
from snackup.identity_models import RefreshSession, User
from snackup.jobs import run_cycle
from snackup.socketio_gateway import Connection, Identity
from test_v3_realtime import access


def test_auth_dependency_returns_sql_connection_before_handler(app, client, tokens):
    @app.get('/api/probe-transaction', include_in_schema=False)
    def probe(db=Depends(get_db, scope='function'), user=Depends(auth.request_user)):
        assert not db.in_transaction()
        assert user.id == 'student'
        return {'released': True}
    assert client.get('/api/probe-transaction', headers=tokens['student']).json() == {'released': True}


def test_pool_timeout_is_retryable_json(app, client):
    @app.get('/api/probe-timeout', include_in_schema=False)
    def probe():
        raise PoolTimeoutError('private SQL details')
    response = client.get('/api/probe-timeout')
    assert response.status_code == 503 and response.headers['Retry-After'] == '1'
    assert response.json()['error']['code'] == 'DATABASE_UNAVAILABLE'
    assert 'private' not in response.text


def test_password_verification_releases_connection_and_rechecks_revocation(app, client, monkeypatch):
    original = auth.password_matches
    def verify(password, encoded):
        assert app.state.db.engine.pool.checkedout() == 0
        with app.state.db.sessions.begin() as db:
            user = db.get(User, 'student')
            auth.revoke_user_sessions(db, user)
        return original(password, encoded)
    monkeypatch.setattr(auth, 'password_matches', verify)
    result = client.post('/api/v1/auth/login', json={'email': 'student@students.example.edu', 'password': 'Test-Only-Password-392!'})
    assert result.status_code == 401
    with app.state.db.sessions() as db:
        assert not db.scalar(select(RefreshSession.id))


def test_batched_socket_auth_uses_constant_queries_and_observes_revocation(app, tokens):
    gateway = app.state.socketio_gateway
    token = access(tokens, 'student')
    connections = [(str(i), Connection(token, Identity('student', 'user', None))) for i in range(250)]
    queries = []
    def capture(conn, cursor, statement, parameters, context, many):
        queries.append(statement)
    event.listen(app.state.db.engine, 'before_cursor_execute', capture)
    try:
        assert len(gateway._validate_batch(connections, 'business:business-1:products')) == 250
    finally:
        event.remove(app.state.db.engine, 'before_cursor_execute', capture)
    assert len(queries) == 2
    with app.state.db.sessions.begin() as db:
        auth.revoke_user_sessions(db, db.get(User, 'student'))
    assert not gateway._validate_batch(connections, 'business:business-1:products')


def test_outbox_retention_preserves_unpublished_and_recent_events(app):
    now = utcnow()
    with app.state.db.sessions.begin() as db:
        db.add_all([OutboxEvent(event_id='a'*32, topic='test', event_type='test', data={}, published_at=now-timedelta(days=8)),
                    OutboxEvent(event_id='b'*32, topic='test', event_type='test', data={}, published_at=now-timedelta(days=1)),
                    OutboxEvent(event_id='c'*32, topic='test', event_type='test', data={}, created_at=now-timedelta(days=8))])
    run_cycle(app.state.db, app.state.settings, now)
    with app.state.db.sessions() as db:
        assert set(db.scalars(select(OutboxEvent.event_id))) == {'b'*32, 'c'*32}


def test_silent_redis_subscription_survives_past_old_timeout(app, caplog):
    url = os.environ.get('SNACKUP_TEST_REDIS_URL')
    if not url:
        pytest.skip('Real isolated Redis required')
    from snackup.realtime import EventBridge, CHANNEL
    from redis.asyncio import Redis
    app.state.settings.redis_url = url
    bridge = EventBridge(app.state.db, app.state.settings)
    async def exercise():
        seen = asyncio.Queue()
        bridge.add_listener(seen.put_nowait)
        task = asyncio.create_task(bridge.subscribe_loop())
        redis = Redis.from_url(url)
        try:
            await asyncio.wait_for(bridge.subscription_ready.wait(), 5)
            await asyncio.sleep(7)
            assert bridge.subscription_ready.is_set()
            await redis.publish(CHANNEL, '{"type":"probe.silence"}')
            assert (await asyncio.wait_for(seen.get(), 2))['type'] == 'probe.silence'
        finally:
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
            await bridge.subscriber.aclose()
            bridge.redis.close()
            await redis.aclose()
    asyncio.run(exercise())
    assert not any('Event subscription unavailable' in r.message for r in caplog.records)


def test_admission_bounds_concurrency_without_thread_or_connection_wait():
    from snackup.admission import DatabaseAdmission
    from starlette.responses import JSONResponse
    async def exercise():
        active = peak = 0
        started = asyncio.Event()
        release = asyncio.Event()
        async def endpoint(scope, receive, send):
            nonlocal active, peak
            active += 1
            peak = max(peak, active)
            started.set()
            try:
                await release.wait()
                await JSONResponse({'ok': True})(scope, receive, send)
            finally:
                active -= 1
        middleware = DatabaseAdmission(endpoint, capacity=1, wait_seconds=.02)
        async def request():
            messages = []
            async def receive():
                return {'type': 'http.request', 'body': b''}
            async def send(message):
                messages.append(message)
            await middleware({'type': 'http', 'path': '/api/probe'}, receive, send)
            return messages
        first = asyncio.create_task(request())
        await started.wait()
        rejected = await request()
        assert rejected[0]['status'] == 503
        assert (b'retry-after', b'1') in rejected[0]['headers']
        release.set()
        assert (await first)[0]['status'] == 200
        assert (await request())[0]['status'] == 200
        assert peak == 1 and active == 0
    asyncio.run(exercise())


def test_retention_never_discards_pending_push(app):
    from snackup.push_models import PushDelivery
    now = utcnow()
    with app.state.db.sessions.begin() as db:
        row = OutboxEvent(event_id='d'*32, topic='test', event_type='test', data={}, published_at=now-timedelta(days=8))
        db.add(row)
        db.flush()
        db.add(PushDelivery(outbox_event_id=row.id, event_id=row.event_id, user_id='student', payload={}, state='retry'))
    run_cycle(app.state.db, app.state.settings, now)
    with app.state.db.sessions() as db:
        assert db.scalar(select(OutboxEvent.event_id)) == 'd'*32


def test_http_authorization_joins_session_roster_and_business_in_one_query(app, tokens):
    queries = []
    def capture(conn, cursor, statement, parameters, context, many):
        queries.append(statement)
    event.listen(app.state.db.engine, 'before_cursor_execute', capture)
    try:
        with app.state.db.sessions() as db:
            assert auth.verify_access_token(access(tokens, 'student'), db, app.state.settings).id == 'student'
    finally:
        event.remove(app.state.db.engine, 'before_cursor_execute', capture)
    assert len(queries) == 1


@pytest.mark.postgres
def test_login_waiting_on_actor_observes_business_disabled_during_wait(app, client):
    if app.state.db.engine.dialect.name != 'postgresql':
        pytest.skip('Real PostgreSQL row-lock snapshot required')
    from concurrent.futures import ThreadPoolExecutor
    from threading import Event
    from fastapi.testclient import TestClient
    from snackup.operation_models import Business
    waiting = Event()
    def observe(conn, cursor, statement, parameters, context, many):
        if 'FOR NO KEY UPDATE' in statement and 'users' in statement:
            waiting.set()
    # Keep the app's lifespan owned by the existing client, not this peer.
    def request_login():
        peer = TestClient(app, base_url=app.state.settings.public_origin)
        try:
            return peer.post('/api/v1/auth/login', json={
                'email': 'operator@staff.example.edu', 'password': 'Test-Only-Password-392!'})
        finally:
            peer.close()
    with app.state.db.sessions() as blocker, ThreadPoolExecutor(max_workers=1) as pool:
        blocker.scalar(select(User).where(User.id == 'operator').with_for_update())
        event.listen(app.state.db.engine, 'before_cursor_execute', observe)
        try:
            future = pool.submit(request_login)
            try:
                assert waiting.wait(10), 'Login did not reach actor lock'
                blocker.get(Business, 'business-1').is_active = False
            finally:
                blocker.commit()
            response = future.result(timeout=10)
        finally:
            event.remove(app.state.db.engine, 'before_cursor_execute', observe)
    assert response.status_code == 403, response.text
    assert response.json()['error']['code'] == 'ACCESS_REVOKED'
