import asyncio
import json
import os
from uuid import uuid4

import pytest
from pydantic import ValidationError
from redis import Redis
from sqlalchemy import select

from snackup.config import Settings
from snackup.db import OutboxEvent, emit_event
from snackup.errors import ApiError
from snackup.limits import RateLimiter
from snackup.realtime import CHANNEL, EventBridge


def test_outbox_is_commit_first_and_sql_failure_does_not_publish(app):
    with app.state.db.sessions() as db:
        with db.begin():
            emit_event(db, 'business:business-1:orders', 'order.created', {'id': 'committed', 'version': 1})
    with app.state.db.sessions() as db:
        emit_event(db, 'business:business-1:orders', 'order.created', {'id': 'rolled-back', 'version': 1})
        db.flush()
        db.rollback()

    async def verify():
        bridge = app.state.events
        queue = asyncio.Queue()
        bridge.clients[queue] = {'business:business-1:orders'}
        await bridge.dispatch_once()
        assert queue.get_nowait()['data']['id'] == 'committed'
        assert queue.empty()
        await bridge.dispatch_once()
        assert queue.empty(), 'A published event should not be dispatched again in a successful cycle.'
        bridge.clients.pop(queue)

    asyncio.run(verify())
    with app.state.db.sessions() as db:
        rows = db.scalars(select(OutboxEvent)).all()
        assert len(rows) == 1 and rows[0].published_at is not None


def test_failed_broker_publish_retains_outbox_for_retry(app):
    class OfflineBroker:
        def publish(self, channel, message):
            raise ConnectionError('test broker unavailable')

    with app.state.db.sessions.begin() as db:
        emit_event(db, 'test', 'test.event', {'id': 'retry'})
    app.state.events.redis = OfflineBroker()
    with pytest.raises(ConnectionError):
        app.state.events._dispatch()
    app.state.events.redis = None
    with app.state.db.sessions() as db:
        assert db.scalar(select(OutboxEvent)).published_at is None
    assert app.state.events._dispatch()[0]['data']['id'] == 'retry'


def test_real_redis_rate_limit_and_outbox_publish(app):
    url = os.environ.get('SNACKUP_TEST_REDIS_URL')
    if not url:
        pytest.skip('A dedicated Redis service is required to test the real broker.')
    settings = app.state.settings.model_copy(update={'redis_url': url})
    limiter = RateLimiter(settings)
    identity = uuid4().hex
    broker = Redis.from_url(url)
    bridge = EventBridge(app.state.db, settings)
    try:
        limiter.check('integration', identity, 1, 60)
        # A second limiter instance shares the counter through the real broker.
        second = RateLimiter(settings)
        try:
            with pytest.raises(ApiError) as limited:
                second.check('integration', identity, 1, 60)
            assert limited.value.status == 429
        finally:
            second.close()
        with broker.pubsub() as subscriber:
            subscriber.subscribe(CHANNEL)
            assert subscriber.get_message(timeout=3)['type'] == 'subscribe'
            with app.state.db.sessions.begin() as db:
                emit_event(db, 'integration:' + identity, 'order.updated', {'id': identity, 'version': 1})
            assert bridge._dispatch() == []
            message = subscriber.get_message(timeout=3)
            assert json.loads(message['data'])['data']['id'] == identity
        with app.state.db.sessions() as db:
            assert db.scalar(select(OutboxEvent)).published_at is not None
    finally:
        limiter.close()
        broker.close()
        bridge.redis.close()


def test_production_rejects_development_settings_without_leaking_secret():
    secret = 'secret-that-must-not-appear-in-errors-1234'
    with pytest.raises(ValidationError) as error:
        Settings(environment='production', secret_key=secret, database_url='sqlite:///test.db')
    assert secret not in str(error.value)


def test_unknown_api_routes_do_not_fall_through_to_html(client):
    response = client.get('/api/v1/does-not-exist')
    assert response.status_code == 404
    assert response.json()['error']['code'] == 'NOT_FOUND'
