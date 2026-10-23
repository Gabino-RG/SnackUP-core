"""Regressions discovered during independent backend security review."""
from uuid import uuid4

import pytest
from sqlalchemy import select
from starlette.websockets import WebSocketDisconnect

from snackup.db import OutboxEvent
from snackup.realtime import socket_identity


def test_pending_websockets_count_towards_connection_cap(client, app):
    app.state.settings.max_websockets = 1
    headers = {"Origin": app.state.settings.public_origin}
    # The first socket has not authenticated. It still consumes a connection.
    with client.websocket_connect("/api/v1/realtime", headers=headers):
        with pytest.raises(WebSocketDisconnect) as closed:
            with client.websocket_connect("/api/v1/realtime", headers=headers):
                pytest.fail("The second pending connection bypassed the configured socket cap")
        assert closed.value.code == 1008
    # Closing the pending socket releases capacity for a subsequent connection.
    with client.websocket_connect("/api/v1/realtime", headers=headers):
        pass


@pytest.mark.parametrize("authenticated", [False, True])
def test_binary_websocket_input_closes_cleanly_without_server_exception(client, app, tokens, authenticated):
    with client.websocket_connect("/api/v1/realtime", headers={"Origin": app.state.settings.public_origin}) as ws:
        if authenticated:
            ws.send_json({"action": "auth", "token": tokens["operator"]["Authorization"].removeprefix("Bearer ")})
            ws.send_json({"action": "subscribe", "topics": ["business:business-1:orders"]})
            assert ws.receive_json()["type"] == "subscribed"
        ws.send_bytes(b"not a text protocol message")
        assert ws.receive_json()["type"] == "unauthorized"
        with pytest.raises(WebSocketDisconnect) as closed:
            ws.receive_json()
        assert closed.value.code == 1008


def test_student_order_outbox_uses_the_authorized_student_topic(client, app, tokens):
    created = client.post("/api/v1/student/orders", headers={**tokens["student"], "Idempotency-Key": uuid4().hex},
                          json={"businessId": "business-1", "items": [{"productId": "product-1", "quantity": 1}]})
    assert created.status_code == 201, created.text
    token = tokens["student"]["Authorization"].removeprefix("Bearer ")
    permitted = socket_identity(app, token)
    with app.state.db.sessions() as db:
        events = db.scalars(select(OutboxEvent).where(OutboxEvent.event_type == "order.created")).all()
        student_events = [event for event in events if event.topic in permitted]
        assert len(student_events) == 1
        assert student_events[0].data == {"id": created.json()["id"], "version": 1, "status": "pending"}
        assert "pickupCode" not in str([event.data for event in events])
        assert "institutionalId" not in str([event.data for event in events])
