"""Wire-level private chat and scheduler events, including post-close retries."""
import json

import pytest
from sqlalchemy import select

from snackup.db import OutboxEvent, utcnow
from test_v3_realtime import access, connected, packet, subscribe


@pytest.mark.parametrize('who,topic', [
    ('student', 'user:other-student:chats'), ('student', 'business:business-1:chats'),
    ('operator', 'business:business-2:chats'), ('operator', 'user:student:chats'),
    ('admin', 'business:business-1:chats'), ('admin', 'user:student:chats'),
])
def test_chat_topics_are_private(client, tokens, who, topic):
    with connected(client, access(tokens, who)) as ws:
        assert subscribe(ws, [topic]) == {'ok': False, 'error': {'code': 'FORBIDDEN'}}


def test_message_text_only_materializes_for_authorized_active_chat(client, tokens, app):
    chat = client.post('/api/v1/businesses/business-1/chats', headers=tokens['student'], json={}).json()
    route = '/api/v1/chats/' + chat['id']
    with connected(client, access(tokens, 'operator')) as ws:
        assert subscribe(ws, ['business:business-1:chats'])['ok']
        client.post(route + '/messages', headers=tokens['student'], json={'text': 'Mensaje temporal de prueba'})
        with app.state.db.sessions() as db:
            row = db.scalar(select(OutboxEvent).where(OutboxEvent.event_type == 'chat.message',
                              OutboxEvent.topic == 'business:business-1:chats'))
            event = {'id': row.event_id, 'type': row.event_type, 'topic': row.topic,
                     'occurredAt': utcnow().isoformat(), 'data': row.data}
            assert 'text' not in row.data
        client.portal.call(app.state.socketio_gateway.emit_event, event)
        name, received = json.loads(packet(ws)[2:])
        assert name == 'chat.message' and received['data']['text'] == 'Mensaje temporal de prueba'
        assert not {'senderId', 'pickupCode', 'orderId'} & received['data'].keys()
        assert client.delete(route, headers=tokens['student']).status_code == 204
        # Queued/retried old notifications cannot resurrect a deleted message.
        client.portal.call(app.state.socketio_gateway.emit_event, event)
        # An ACK gives a deterministic barrier: any leaked packet would arrive first.
        assert subscribe(ws, ['business:business-1:chats'], number=2)['ok']


def test_pickup_alert_removes_secrets(client, tokens, app):
    with connected(client, access(tokens, 'operator')) as ws:
        assert subscribe(ws, ['business:business-1:orders'])['ok']
        event = {'id': 'alert', 'type': 'order.pickup_soon', 'topic': 'business:business-1:orders',
                 'occurredAt': utcnow().isoformat(), 'data': {'id': 'order', 'businessId': 'business-1',
                    'scheduledPickupTime': utcnow().isoformat(), 'pickupCode': 'SECRET'}}
        client.portal.call(app.state.socketio_gateway.emit_event, event)
        assert 'SECRET' not in packet(ws)
