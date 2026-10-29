"""Durable delivery, recipient authorization, and actual provider adapters.

Provider HTTP is replaced at its transport boundary. No test contacts a push
service, and passing tests do not certify deployment credentials or a handset.
"""
from datetime import timedelta
from decimal import Decimal
import json
from types import SimpleNamespace

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
import httpx
import jwt
import pytest
from sqlalchemy import select

from snackup.db import OutboxEvent, emit_event, utcnow
from snackup.identity_models import RefreshSession, User
from snackup.operation_models import Order
from snackup.push import APNSProvider, FCMProvider, PushResult, WebPushProvider
from snackup.push_models import Device, PushDelivery
from test_v3_devices import login, register, subscription

pytestmark = pytest.mark.v3


class FakeProvider:
    def __init__(self, *results):
        self.results = list(results) or [PushResult("accepted", message_id="provider-message")]
        self.calls = []

    def send(self, token, payload):
        self.calls.append((token, payload))
        return self.results.pop(0) if len(self.results) > 1 else self.results[0]


def recipients(client):
    student, student_tokens = login(client)
    operator, _ = login(client, "operator")
    other, _ = login(client, "other-operator")
    for headers, token in ((student, "student-private-push-token-111"),
                           (operator, "operator-private-push-token-222"), (other, "other-private-push-token-333")):
        assert register(client, headers, token).status_code == 201
    return student, student_tokens, operator


def enqueue(app, state="pending", created=True, actor=None, rating=False):
    with app.state.db.sessions.begin() as db:
        order = db.get(Order, "order-push-test")
        if order is None:
            order = Order(id="order-push-test", business_id="business-1", student_id="student", order_number=1051,
                customer_name="PRIVATE CUSTOMER", customer_institutional_id="PRIVATE MATRICULA", total=Decimal("35.50"),
                pickup_code="963852", status=state, version=1)
            db.add(order)
            db.flush()
        else:
            order.status, order.version = state, order.version + 1
        order.cancelled_by_role = actor
        data = {"id": order.id, "businessId": order.business_id, "status": state, "version": order.version,
                "pickupCode": "963852", "matricula": "PRIVATE MATRICULA"}
        if rating:
            data.update(change="rating", isRated=True)
        for topic in ["business:business-1:orders", "user:student:orders"]:
            emit_event(db, topic, "order.created" if created else "order.updated", data)
    app.state.events._dispatch()


def deliveries(app):
    with app.state.db.sessions() as db:
        return db.scalars(select(PushDelivery).order_by(PushDelivery.created_at)).all()


def test_new_order_targets_only_its_kitchen_and_sanitizes_durable_payload(client, app):
    recipients(client)
    enqueue(app)
    app.state.settings.push_enabled = True
    provider = FakeProvider()
    app.state.push.providers = {"fcm": provider}
    jobs = deliveries(app)
    assert len(jobs) == 1 and jobs[0].user_id == "operator"
    assert jobs[0].payload["title"] == "Nuevo pedido #1051"
    text = json.dumps(jobs[0].payload)
    assert "PRIVATE" not in text and "963852" not in text and "pickupCode" not in text
    assert client.portal.call(app.state.push.dispatch_once) == 1
    assert len(provider.calls) == 1 and provider.calls[0][0] == "operator-private-push-token-222"
    sent = deliveries(app)[0]
    assert sent.state == "sent" and sent.attempts == 1 and sent.sent_at is not None
    assert sent.provider_message_id == "provider-message"
    assert client.portal.call(app.state.push.dispatch_once) == 0


@pytest.mark.parametrize("state,actor,target,title", [
    ("accepted", None, "student", "Pedido confirmado"), ("ready", None, "student", "¡Tu pedido está listo!"),
    ("completed", None, "student", "¿Cómo estuvo tu pedido?"),
    ("cancelled", "ALUMNO", "operator", "Pedido cancelado"), ("cancelled", "COCINA", "student", "Pedido cancelado"),
])
def test_push_transition_recipient_and_message(client, app, state, actor, target, title):
    recipients(client)
    enqueue(app, state=state, created=False, actor=actor)
    jobs = deliveries(app)
    assert len(jobs) == 1 and jobs[0].user_id == target and jobs[0].payload["title"] == title
    if state == "completed":
        assert jobs[0].payload["data"]["action"] == "review"


def test_preparing_and_rating_updates_do_not_generate_push(client, app):
    recipients(client)
    enqueue(app, state="preparing", created=False)
    enqueue(app, state="completed", created=False, rating=True)
    assert not deliveries(app)


def test_missing_credentials_are_persisted_as_unconfigured_with_backoff(client, app):
    recipients(client)
    enqueue(app)
    app.state.settings.push_enabled = True
    client.portal.call(app.state.push.dispatch_once)
    job = deliveries(app)[0]
    assert job.state == "unconfigured" and job.attempts == 0 and job.sent_at is None
    assert job.last_error == "PROVIDER_NOT_CONFIGURED"
    assert client.portal.call(app.state.push.dispatch_once) == 0


def test_transient_error_retries_durably_and_recovers_expired_worker_lease(client, app):
    recipients(client)
    enqueue(app)
    app.state.settings.push_enabled = True
    provider = FakeProvider(PushResult("retry", "PROVIDER_TEMPORARY", retry_after=120), PushResult("accepted"))
    app.state.push.providers = {"fcm": provider}
    client.portal.call(app.state.push.dispatch_once)
    first = deliveries(app)[0]
    assert first.state == "retry" and first.attempts == 1 and first.sent_at is None
    assert first.last_error == "PROVIDER_TEMPORARY"
    assert client.portal.call(app.state.push.dispatch_once) == 0
    with app.state.db.sessions.begin() as db:
        job = db.get(PushDelivery, first.id)
        job.state, job.lease_id = "sending", "dead-worker"
        job.locked_until = utcnow() - timedelta(seconds=1)
    assert client.portal.call(app.state.push.dispatch_once) == 1
    final = deliveries(app)[0]
    assert final.state == "sent" and final.attempts == 2 and len(provider.calls) == 2


def test_max_attempts_stop_retry_and_invalid_provider_token_is_removed(client, app):
    recipients(client)
    enqueue(app)
    app.state.settings.push_enabled = True
    app.state.settings.push_max_attempts = 1
    app.state.push.providers = {"fcm": FakeProvider(PushResult("retry", "PROVIDER_TEMPORARY"))}
    client.portal.call(app.state.push.dispatch_once)
    assert deliveries(app)[0].state == "dead"
    enqueue(app, state="ready", created=False)
    app.state.push.providers = {"fcm": FakeProvider(PushResult("invalid", "TOKEN_INVALID"))}
    client.portal.call(app.state.push.dispatch_once)
    assert all(job.state == "dead" for job in deliveries(app))
    with app.state.db.sessions() as db:
        assert db.scalar(select(Device.id).where(Device.user_id == "student")) is None
        assert db.scalar(select(Device.id).where(Device.user_id == "operator")) is not None


@pytest.mark.parametrize("revoke", ["logout", "account", "superseded"])
def test_logout_revocation_and_superseded_state_block_pending_delivery(client, app, revoke):
    student, tokens, _ = recipients(client)
    enqueue(app, state="ready", created=False)
    app.state.settings.push_enabled = True
    provider = FakeProvider()
    app.state.push.providers = {"fcm": provider}
    if revoke == "logout":
        assert client.post("/api/v1/auth/logout", headers=student,
                           json={"refreshToken": tokens["refreshToken"]}).status_code == 204
    else:
        with app.state.db.sessions.begin() as db:
            if revoke == "account":
                db.get(User, "student").auth_version += 1
            else:
                db.get(Order, "order-push-test").status = "completed"
    client.portal.call(app.state.push.dispatch_once)
    assert not provider.calls
    assert deliveries(app)[0].state == "cancelled"


def test_failed_redis_publish_retains_attempt_and_deduplicates_durable_push(client, app):
    recipients(client)
    class Offline:
        def publish(self, *args):
            raise ConnectionError("simulated broker outage")
    app.state.events.redis = Offline()
    try:
        with pytest.raises(ConnectionError):
            enqueue(app)
        with app.state.db.sessions() as db:
            row = db.scalar(select(OutboxEvent).where(OutboxEvent.publish_attempts == 1))
            assert row.published_at is None and row.last_error == "REDIS_PUBLISH_FAILED" and row.next_attempt_at is not None
        assert len(deliveries(app)) == 1
    finally:
        app.state.events.redis = None
    app.state.events._dispatch()
    app.state.events._dispatch()
    assert len(deliveries(app)) == 1


def test_fcm_adapter_uses_oauth_http_v1_and_classifies_unregistered(app, monkeypatch, tmp_path):
    settings = app.state.settings
    settings.push_fcm_credentials_file = tmp_path / "not-read-for-cached-credentials.json"
    settings.push_fcm_project_id = "snackup-test-project"
    provider = FCMProvider(settings)
    provider.credentials = SimpleNamespace(valid=True, token="fake-oauth-access")
    captured = []
    def send(client, url, **kwargs):
        captured.append((url, kwargs))
        return httpx.Response(404, json={"error": {"details": [{"errorCode": "UNREGISTERED"}]}})
    monkeypatch.setattr(httpx.Client, "post", send)
    result = provider.send("private-device-token", {"title": "Pedido confirmado", "body": "Abre SnackUP", "data": {"version": 2}})
    assert result.kind == "invalid"
    assert captured[0][0] == "https://fcm.googleapis.com/v1/projects/snackup-test-project/messages:send"
    assert captured[0][1]["headers"]["Authorization"] == "Bearer fake-oauth-access"
    assert captured[0][1]["json"]["message"]["data"] == {"version": "2"}


def test_apns_adapter_signs_es256_and_uses_fixed_http2_endpoint(app, monkeypatch, tmp_path):
    private = ec.generate_private_key(ec.SECP256R1())
    key_file = tmp_path / "apns-test.p8"
    key_file.write_bytes(private.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                              serialization.NoEncryption()))
    settings = app.state.settings
    settings.push_apns_key_file, settings.push_apns_key_id = key_file, "KEY1234567"
    settings.push_apns_team_id, settings.push_apns_topic = "TEAM123456", "test.snackup.app"
    captured = []
    def send(client, url, **kwargs):
        captured.append((url, kwargs))
        return httpx.Response(200, headers={"apns-id": "accepted-apns-request"})
    monkeypatch.setattr(httpx.Client, "post", send)
    result = APNSProvider(settings).send("a" * 64, {"title": "Listo", "body": "Abre SnackUP", "data": {"orderId": "order"}})
    assert result.kind == "accepted"
    assert captured[0][0] == "https://api.push.apple.com/3/device/" + "a" * 64
    headers = captured[0][1]["headers"]
    claims = jwt.decode(headers["authorization"].removeprefix("bearer "), private.public_key(), algorithms=["ES256"])
    assert claims["iss"] == "TEAM123456" and headers["apns-topic"] == "test.snackup.app"
    assert headers["apns-push-type"] == "alert"


def test_webpush_adapter_encrypts_payload_and_disables_redirects(app, monkeypatch, tmp_path):
    import requests
    private = ec.generate_private_key(ec.SECP256R1())
    key_file = tmp_path / "vapid-test.pem"
    key_file.write_bytes(private.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                              serialization.NoEncryption()))
    app.state.settings.push_webpush_private_key_file = key_file
    app.state.settings.push_webpush_subject = "mailto:operations@example.invalid"
    captured = []
    def request(session, method, url, **kwargs):
        captured.append((method, url, kwargs))
        result = requests.Response()
        result.status_code, result._content = 201, b""
        return result
    monkeypatch.setattr(requests.Session, "request", request)
    result = WebPushProvider(app.state.settings).send(json.dumps(subscription()),
        {"title": "Pedido confirmado", "body": "Abre SnackUP", "data": {"orderId": "order"}})
    assert result.kind == "accepted"
    method, url, kwargs = captured[0]
    assert method == "POST" and url.startswith("https://fcm.googleapis.com/")
    assert kwargs["allow_redirects"] is False and kwargs["timeout"] == app.state.settings.push_http_timeout_seconds
    assert kwargs["headers"]["content-encoding"] == "aes128gcm"
    assert b"Pedido confirmado" not in kwargs["data"]
