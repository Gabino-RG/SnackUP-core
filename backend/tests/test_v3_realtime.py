"""Actual Engine.IO/Socket.IO frames over the mounted ASGI WebSocket path."""
from contextlib import contextmanager
from datetime import timedelta
import json
import os
import time
from uuid import uuid4

import jwt
import pytest
from fastapi.testclient import TestClient
from redis import Redis
from sqlalchemy import select
from starlette.websockets import WebSocketDisconnect

from snackup.db import OutboxEvent, emit_event, utcnow
from snackup.identity_models import RefreshSession, User
from snackup.main import create_app
from snackup.operation_models import Business

pytestmark = pytest.mark.v3
PATH = "/socket.io/?EIO=4&transport=websocket"
UPGRADE = {"Upgrade": "websocket"}


def packet(ws):
    while True:
        value = ws.receive_text()
        if value == "2":
            ws.send_text("3")
        else:
            return value


@contextmanager
def connected(client, token, origin="http://testserver"):
    with client.websocket_connect(PATH, headers={**UPGRADE, "Origin": origin}) as ws:
        assert packet(ws).startswith("0{")
        ws.send_text("40" + json.dumps({"token": token}))
        result = packet(ws)
        assert result.startswith("40{"), result
        yield ws


def subscribe(ws, topics, action="subscribe", number=1):
    ws.send_text("42" + str(number) + json.dumps([action, {"topics": topics}]))
    response = packet(ws)
    assert response.startswith("43" + str(number)), response
    return json.loads(response[len("43" + str(number)):])[0]


def access(tokens, identity):
    return tokens[identity]["Authorization"].removeprefix("Bearer ")


def test_socketio_wire_uses_websocket_handshake_and_filters_order_data(client, app, tokens):
    with connected(client, access(tokens, "student")) as ws:
        assert subscribe(ws, ["room_user_student"])["topics"] == ["user:student:orders"]
        event = {"id": "event-1", "type": "order.updated", "topic": "user:student:orders",
                 "occurredAt": utcnow().isoformat(), "data": {"id": "order-1", "businessId": "business-1",
                     "status": "ready", "version": 4, "pickupCode": "938271", "numeroDeControl": "PRIVATE",
                     "customer": {"matricula": "PRIVATE"}, "refreshToken": "PRIVATE"}}
        client.portal.call(app.state.socketio_gateway.emit_event, event)
        kind, received = json.loads(packet(ws)[2:])
        assert kind == "order.updated" and received["id"] == "event-1"
        assert received["occurredAt"] == event["occurredAt"]
        assert set(received["data"]) == {"id", "businessId", "status", "version"}
        assert "PRIVATE" not in json.dumps(received) and "938271" not in json.dumps(received)
        assert subscribe(ws, ["room_user_student"], "unsubscribe", 2) == {"ok": True, "topics": []}


@pytest.mark.parametrize("identity,topic", [
    ("student", "user:other-student:orders"), ("student", "business:business-1:orders"),
    ("operator", "business:business-2:orders"), ("operator", "room_user_student"),
    ("operator", "business:business-2"), ("operator", "business:business-2:products"),
    ("admin", "room_business_business-1"), ("admin", "user:student:orders"),
])
def test_private_rooms_cannot_cross_user_business_or_role(client, tokens, identity, topic):
    with connected(client, access(tokens, identity)) as ws:
        assert subscribe(ws, [topic]) == {"ok": False, "error": {"code": "FORBIDDEN"}}


@pytest.mark.parametrize("identity", ["student", "operator", "admin"])
def test_authenticated_catalog_subscriptions_and_real_sql_outbox(client, app, tokens, identity):
    business = "business-1" if identity == "operator" else "business-2"
    with connected(client, access(tokens, identity)) as ws:
        assert subscribe(ws, [f"business:{business}", f"business:{business}:products"])["ok"]
        with app.state.db.sessions.begin() as db:
            emit_event(db, f"business:{business}:products", "product.updated", {
                "id": "catalog-product", "businessId": business, "stock": 0, "isAvailable": False,
                "version": 3, "pickupCode": "FORBIDDEN"})
        client.portal.call(app.state.events.dispatch_once)
        kind, event = json.loads(packet(ws)[2:])
        assert kind == "product.updated" and event["data"]["stock"] == 0
        assert event["occurredAt"] and "pickupCode" not in event["data"]
        with app.state.db.sessions() as db:
            assert db.scalar(select(OutboxEvent)).published_at is not None


@pytest.mark.parametrize("query,origin", [
    ("&token=credential-in-url", "http://testserver"), ("&accessToken=credential", "http://testserver"),
    ("", "https://other-origin.invalid"),
])
def test_query_credentials_and_foreign_origins_are_rejected(client, query, origin):
    with pytest.raises(WebSocketDisconnect) as closed:
        with client.websocket_connect(PATH + query, headers={**UPGRADE, "Origin": origin}):
            pytest.fail("Forbidden Socket.IO handshake was accepted")
    assert closed.value.code == 1008


def test_no_http_polling_transport_or_cookie_authentication(client, tokens):
    assert client.get("/socket.io/?EIO=4&transport=polling").status_code == 400
    with client.websocket_connect(PATH, headers=UPGRADE) as ws:
        assert packet(ws).startswith("0{")
        ws.send_text("40")
        assert packet(ws).startswith("44"), "A refresh cookie is not Socket.IO authentication"


def test_expired_handshake_and_revoked_before_emit_fail_closed(client, app, tokens):
    token = access(tokens, "student")
    claims = jwt.decode(token, options={"verify_signature": False})
    claims["exp"] = int(time.time()) - 1
    expired = jwt.encode(claims, app.state.settings.secret_key, algorithm="HS256")
    with client.websocket_connect(PATH, headers=UPGRADE) as ws:
        packet(ws)
        ws.send_text("40" + json.dumps({"token": expired}))
        rejected = packet(ws)
        assert rejected.startswith("44") and "TOKEN_EXPIRED" in rejected
    with connected(client, token) as ws:
        assert subscribe(ws, ["user:student:orders"])["ok"]
        with app.state.db.sessions.begin() as db:
            user = db.get(User, "student")
            user.auth_version += 1
        client.portal.call(app.state.socketio_gateway.emit_event, {
            "id": "revoked", "type": "order.updated", "topic": "user:student:orders",
            "data": {"id": "private", "status": "ready", "version": 1}})
        assert packet(ws) == "41"


def test_periodic_revocation_disconnects_an_idle_connection(client, app, tokens):
    app.state.settings.websocket_revalidate_seconds = 1
    token = access(tokens, "operator")
    sid = jwt.decode(token, options={"verify_signature": False})["sid"]
    with connected(client, token) as ws:
        with app.state.db.sessions.begin() as db:
            db.get(RefreshSession, sid).revoked_at = utcnow()
        started = time.monotonic()
        assert packet(ws) == "41"
        assert time.monotonic() - started < 3


def test_unauthenticated_socketio_connections_share_legacy_capacity(client, app):
    app.state.settings.max_websockets = 1
    with client.websocket_connect(PATH, headers=UPGRADE) as ws:
        packet(ws)
        with pytest.raises(WebSocketDisconnect) as closed:
            with client.websocket_connect("/api/legacy/v1/realtime", headers={"Origin": "http://testserver"}):
                pytest.fail("Pending Socket.IO connection did not reserve capacity")
        assert closed.value.code == 1008


def test_socketio_auth_deadline_cannot_be_extended_by_unauthed_pongs(client, app):
    app.state.socketio_gateway.handshake_timeout_seconds = 0.2
    with client.websocket_connect(PATH, headers=UPGRADE) as ws:
        packet(ws)
        ws.send_text("3")
        with pytest.raises(WebSocketDisconnect) as closed:
            packet(ws)
        assert closed.value.code == 1008


def test_redis_delivers_committed_event_to_socketio_clients_on_two_workers(client, app, tokens):
    url = os.environ.get("SNACKUP_TEST_REDIS_URL")
    if not url:
        pytest.skip("A dedicated Redis service is required for cross-worker delivery.")
    business_id = "redis-business-" + uuid4().hex
    with app.state.db.sessions.begin() as db:
        db.add(Business(id=business_id, name="Isolated test catalog", cafeteria_id="test", cafeteria_name="Test"))
    app.state.settings.redis_url = url
    app.state.events.redis = Redis.from_url(url, socket_timeout=2, socket_connect_timeout=2)
    peer = create_app(app.state.settings.model_copy())
    with TestClient(peer) as second:
        with connected(client, access(tokens, "student")) as first_ws, connected(second, access(tokens, "student")) as second_ws:
            topic = f"business:{business_id}:products"
            assert subscribe(first_ws, [topic])["ok"]
            assert subscribe(second_ws, [topic])["ok"]
            client.portal.call(app.state.events.start)
            second.portal.call(peer.state.events.start)
            with app.state.db.sessions.begin() as db:
                emit_event(db, topic, "product.updated", {"id": "shared-product", "businessId": business_id,
                                                          "stock": 2, "version": 8})
            client.portal.call(app.state.events.dispatch_once)
            one, two = json.loads(packet(first_ws)[2:]), json.loads(packet(second_ws)[2:])
            assert one == two and one[0] == "product.updated" and one[1]["data"]["version"] == 8
