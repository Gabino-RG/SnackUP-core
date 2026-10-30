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


def test_order_handlers_release_locks_before_returning_to_event_loop(app, client, tokens, monkeypatch):
    from uuid import uuid4
    checked = []
    from snackup import v3_operations
    for name, db_position in (('create_order_transaction', 2), ('_transition_response', 0)):
        original = getattr(v3_operations, name)
        def handler(*args, _original=original, _db_position=db_position, **kwargs):
            result = _original(*args, **kwargs)
            assert not args[_db_position].in_transaction(), 'Hot row locks survived the handler thread'
            checked.append(True)
            return result
        monkeypatch.setattr(v3_operations, name, handler)
    headers = {**tokens['student'], 'Idempotency-Key': str(uuid4())}
    payload = {'businessId': 'business-1', 'items': [{'productId': 'product-1', 'quantity': 1}], 'expectedTotal': 35.5}
    created = client.post('/api/v1/orders', headers=headers, json=payload)
    repeated = client.post('/api/v1/orders', headers=headers, json=payload)
    assert created.status_code == repeated.status_code == 201
    assert created.content == repeated.content
    cancelled = client.post('/api/v1/orders/' + created.json()['id'] + '/cancel', headers=tokens['student'],
                            json={'reason': 'user_other', 'notes': 'Prueba de liberación de bloqueos'})
    assert cancelled.status_code == 200
    assert len(checked) == 3


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


@pytest.mark.parametrize('blocked_on', ['write-slot', 'global-slot'])
def test_waiting_writes_allow_reads_and_release_permits_on_timeout_and_cancel(blocked_on):
    from snackup.admission import DatabaseAdmission
    from starlette.responses import JSONResponse
    async def exercise():
        started, release = asyncio.Event(), asyncio.Event()
        async def endpoint(scope, receive, send):
            if scope['path'].endswith('block'):
                started.set()
                await release.wait()
            await JSONResponse({'ok': True})(scope, receive, send)
        middleware = DatabaseAdmission(endpoint, capacity=3 if blocked_on == 'write-slot' else 1,
                                       wait_seconds=.03, write_concurrency=1)
        async def request(method, path='/api/probe'):
            messages = []
            async def receive():
                return {'type': 'http.request', 'body': b''}
            async def send(message):
                messages.append(message)
            await middleware({'type': 'http', 'method': method, 'path': path}, receive, send)
            return messages[0]['status']
        first = asyncio.create_task(request('POST' if blocked_on == 'write-slot' else 'GET', '/api/block'))
        await started.wait()
        if blocked_on == 'write-slot':
            assert await request('GET') == 200
        assert await request('POST') == 503
        cancelled = asyncio.create_task(request('POST'))
        await asyncio.sleep(0)
        cancelled.cancel()
        with pytest.raises(asyncio.CancelledError):
            await cancelled
        release.set()
        assert await first == 200
        assert await request('POST') == 200
    asyncio.run(exercise())


async def _admit(middleware, method, path, headers=()):
    messages = []
    async def receive():
        return {'type': 'http.request', 'body': b''}
    async def send(message):
        messages.append(message)
    await middleware({'type': 'http', 'method': method, 'path': path, 'headers': list(headers)}, receive, send)
    return messages[0]['status']


def test_mail_and_session_requests_never_take_the_write_slot():
    """Phase C B-12: a 16 s SMTP left kitchens with 503 for the whole send."""
    from snackup.admission import DatabaseAdmission
    from starlette.responses import JSONResponse
    async def exercise():
        started, release = asyncio.Event(), asyncio.Event()
        async def endpoint(scope, receive, send):
            if scope['path'].endswith(('/forgot-password', '/refresh')):
                started.set()
                await release.wait()
            await JSONResponse({'ok': True})(scope, receive, send)
        middleware = DatabaseAdmission(endpoint, capacity=4, wait_seconds=.03, write_concurrency=1,
                                       mail_concurrency=1, session_concurrency=1)
        mail = asyncio.create_task(_admit(middleware, 'POST', '/api/v1/auth/forgot-password'))
        await started.wait()
        started.clear()
        session = asyncio.create_task(_admit(middleware, 'POST', '/api/legacy/v1/auth/refresh'))
        await started.wait()
        assert await _admit(middleware, 'POST', '/api/v1/orders') == 200
        assert await _admit(middleware, 'PATCH', '/api/v1/orders/o-1/status') == 200
        # Each lane still bounds itself.
        assert await _admit(middleware, 'POST', '/api/v1/auth/resend-verification') == 503
        assert await _admit(middleware, 'POST', '/api/v1/auth/logout') == 503
        release.set()
        assert (await mail, await session) == (200, 200)
    asyncio.run(exercise())


def test_login_wave_waits_in_its_lane_and_leaves_slots_for_reads():
    """Phase C B-13: logins queued for Argon2 held every slot; reads stalled ~3 s."""
    from snackup.admission import DatabaseAdmission
    from starlette.responses import JSONResponse
    async def exercise():
        started, release = asyncio.Event(), asyncio.Event()
        async def endpoint(scope, receive, send):
            if scope['path'].endswith('/auth/login'):
                started.set()
                await release.wait()
            await JSONResponse({'ok': True})(scope, receive, send)
        middleware = DatabaseAdmission(endpoint, capacity=2, wait_seconds=.03, login_wait_seconds=.05,
                                       login_concurrency=1)
        first = asyncio.create_task(_admit(middleware, 'POST', '/api/v1/auth/login'))
        await started.wait()
        second = asyncio.create_task(_admit(middleware, 'POST', '/api/v1/auth/login'))
        await asyncio.sleep(0)
        assert await _admit(middleware, 'GET', '/api/v1/businesses') == 200
        assert await second == 503
        release.set()
        assert await first == 200
    asyncio.run(exercise())


@pytest.mark.parametrize('path, lane', [
    ('/api/v1/auth/register', 'mail'), ('/api/legacy/v1/student/register', 'mail'),
    ('/api/v1/admin/users/u-1/reset-password', 'mail'), ('/api/legacy/v1/auth/forgot-password', 'mail'),
    ('/api/v1/auth/refresh', 'session'), ('/api/v1/auth/logout', 'session'), ('/api/legacy/v1/auth/login', 'login'),
    ('/api/v1/orders', 'write'), ('/api/v1/admin/users/u-1/reset-password/x', 'write'),
    ('/api/v1/auth/register-extra', 'write'),
])
def test_admission_lane_classification(path, lane):
    from snackup.admission import DatabaseAdmission
    middleware = DatabaseAdmission(None, capacity=4, wait_seconds=1)
    assert middleware.lane({'method': 'POST', 'path': path}) == lane
    assert middleware.lane({'method': 'GET', 'path': path}) is None


def test_time_queued_before_admission_counts_against_the_wait():
    """Phase C B-14: rejections reached clients at ~8.4 s instead of 5 s."""
    import time
    from snackup.admission import DatabaseAdmission
    from starlette.responses import JSONResponse
    async def exercise():
        started, release = asyncio.Event(), asyncio.Event()
        async def endpoint(scope, receive, send):
            if scope['path'].endswith('block'):
                started.set()
                await release.wait()
            await JSONResponse({'ok': True})(scope, receive, send)
        middleware = DatabaseAdmission(endpoint, capacity=1, wait_seconds=1)
        def stamp(seconds_ago):
            return [(b'x-snackup-edge-ms', str(int((time.time() - seconds_ago) * 1000)).encode())]
        # A free slot is used even when the budget is already spent.
        assert await _admit(middleware, 'GET', '/api/probe', stamp(3)) == 200
        first = asyncio.create_task(_admit(middleware, 'GET', '/api/block'))
        await started.wait()
        clock = time.monotonic()
        assert await _admit(middleware, 'GET', '/api/probe', stamp(3)) == 503
        assert time.monotonic() - clock < .2
        clock = time.monotonic()
        assert await _admit(middleware, 'GET', '/api/probe', stamp(.7)) == 503
        assert .2 < time.monotonic() - clock < .6
        # Missing, malformed or implausible stamps keep the full wait.
        for headers in ([], [(b'x-snackup-edge-ms', b'soon')], stamp(-30), stamp(3600)):
            clock = time.monotonic()
            assert await _admit(middleware, 'GET', '/api/probe', headers) == 503
            assert time.monotonic() - clock >= .9
        release.set()
        assert await first == 200
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
