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
