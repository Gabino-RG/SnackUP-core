"""Device ownership and session isolation through the real V3 HTTP boundary."""
import base64
import json

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
import jwt
import pytest
from sqlalchemy import select

from snackup.identity_models import RefreshSession
from snackup.push_models import Device

pytestmark = pytest.mark.v3
PASSWORD = "Test-Only-Password-392!"


def login(client, identity="student"):
    domain = "students.example.edu" if "student" in identity else "staff.example.edu"
    response = client.post("/api/v1/auth/login", json={"email": identity + "@" + domain, "password": PASSWORD})
    assert response.status_code == 200, response.text
    tokens = response.json()["tokens"]
    return {"Authorization": "Bearer " + tokens["accessToken"]}, tokens


def register(client, headers, token="test-fcm-registration-token-111111", platform="android", provider="fcm"):
    return client.post("/api/v1/users/me/devices", headers=headers,
                       json={"token": token, "platform": platform, "provider": provider})


def subscription(endpoint="https://fcm.googleapis.com/fcm/send/test-installation"):
    public = ec.generate_private_key(ec.SECP256R1()).public_key().public_bytes(
        serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)
    encode = lambda value: base64.urlsafe_b64encode(value).decode().rstrip("=")
    return {"endpoint": endpoint, "expirationTime": None,
            "keys": {"auth": encode(b"only-test-secret"), "p256dh": encode(public)}}


def test_register_hides_token_binds_family_and_refresh_preserves_device(client, app):
    headers, tokens = login(client)
    response = register(client, headers)
    assert response.status_code == 201, response.text
    device = response.json()
    assert set(device) == {"id", "platform", "provider", "lastActiveAt", "createdAt", "updatedAt"}
    assert "test-fcm" not in response.text
    assert register(client, headers).status_code == 200
    sid = jwt.decode(tokens["accessToken"], options={"verify_signature": False})["sid"]
    with app.state.db.sessions() as db:
        session = db.get(RefreshSession, sid)
        assert session.device_id == device["id"]
        assert db.get(Device, device["id"]).session_family_id == session.family_id
    renewed = client.post("/api/v1/auth/refresh", json={"refreshToken": tokens["refreshToken"]})
    assert renewed.status_code == 200, renewed.text
    new_sid = jwt.decode(renewed.json()["tokens"]["accessToken"], options={"verify_signature": False})["sid"]
    with app.state.db.sessions() as db:
        assert db.get(RefreshSession, new_sid).device_id == device["id"]


def test_token_cannot_be_claimed_or_deleted_by_another_user(client, app):
    owner, _ = login(client)
    other, _ = login(client, "other-student")
    device = register(client, owner).json()
    conflict = register(client, other)
    assert conflict.status_code == 409 and conflict.json()["error"]["code"] == "DEVICE_TOKEN_IN_USE"
    assert client.delete("/api/v1/users/me/devices/" + device["id"], headers=other).status_code == 404
    assert client.delete("/api/v1/users/me/devices/" + device["id"], headers=owner).status_code == 204
    with app.state.db.sessions() as db:
        assert db.get(Device, device["id"]) is None
        assert not db.scalars(select(RefreshSession).where(RefreshSession.device_id == device["id"])).all()
    assert register(client, other).status_code == 201


def test_logout_removes_only_its_device_and_old_family_cannot_delete_rebound_token(client, app):
    first, first_tokens = login(client)
    first_device = register(client, first, token="test-fcm-token-first-installation").json()["id"]
    second, second_tokens = login(client)
    second_device = register(client, second, token="test-fcm-token-second-installation").json()["id"]
    assert client.post("/api/v1/auth/logout", headers=first,
                       json={"refreshToken": first_tokens["refreshToken"]}).status_code == 204
    with app.state.db.sessions() as db:
        assert db.get(Device, first_device) is None
        assert db.get(Device, second_device) is not None
    newer, _ = login(client)
    rebound = register(client, newer, token="test-fcm-token-second-installation")
    assert rebound.status_code == 200 and rebound.json()["id"] == second_device
    assert client.post("/api/v1/auth/logout", headers=second,
                       json={"refreshToken": second_tokens["refreshToken"]}).status_code == 204
    with app.state.db.sessions() as db:
        assert db.get(Device, second_device) is not None


@pytest.mark.parametrize("platform,provider,token", [
    ("web", "apns", "a" * 64), ("ios", "webpush", "invalid-json-subscription"),
    ("android", "other", "test-fcm-token-invalid-provider"), ("desktop", "fcm", "test-fcm-token-invalid-platform"),
    ("ios", "apns", "g" * 64), ("android", "fcm", "token containing spaces is invalid"),
])
def test_invalid_platform_provider_and_token_are_rejected(client, platform, provider, token):
    headers, _ = login(client)
    assert register(client, headers, token, platform, provider).status_code == 422


@pytest.mark.parametrize("endpoint", [
    "http://fcm.googleapis.com/fcm/send/x", "https://fcm.googleapis.com.evil.invalid/x",
    "https://127.0.0.1/x", "https://[::1]/x", "https://fcm.googleapis.com:8443/x",
    "https://user:secret@fcm.googleapis.com/x", "https://fcm.googleapis.com/x?token=secret",
])
def test_webpush_refuses_arbitrary_urls(client, endpoint):
    headers, _ = login(client)
    result = register(client, headers, json.dumps(subscription(endpoint)), "web", "webpush")
    assert result.status_code == 422


def test_webpush_endpoint_ownership_survives_json_order_and_key_changes(client, app):
    owner, _ = login(client)
    other, _ = login(client, "other-student")
    value = subscription()
    first = register(client, owner, json.dumps(value), "web", "webpush")
    assert first.status_code == 201, first.text
    same = register(client, owner, json.dumps(value, sort_keys=True, indent=2), "web", "webpush")
    assert same.status_code == 200 and same.json()["id"] == first.json()["id"]
    different_keys = subscription()
    stolen = register(client, other, json.dumps(different_keys), "web", "webpush")
    assert stolen.status_code == 409
    with app.state.db.sessions() as db:
        saved = db.get(Device, first.json()["id"])
        assert len(saved.token_hash) == 64 and saved.user_id == "student"
