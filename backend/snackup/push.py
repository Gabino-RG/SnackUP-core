"""Authenticated device registration and durable push delivery.

Push is an optional notification channel; PostgreSQL/REST remain authoritative.
The SQL outbox records business changes, and PushDelivery records each provider
attempt separately. A provider accepting a request means ``sent`` here, not that
the operating system displayed it or that the recipient read it.
"""
from .auth import request_user

import asyncio
import base64
from dataclasses import dataclass
from datetime import timedelta
from email.utils import parsedate_to_datetime
import hashlib
import json
import logging
import random
import re
import threading
import time
from typing import Literal
from urllib.parse import urlsplit, urlunsplit

from fastapi import APIRouter, Depends, Request, Response
import httpx
import jwt
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import and_, func, or_, select, update
from sqlalchemy.orm import Session

from .auth import as_utc, current_user, ensure_account, verify_access_token
from .db import get_db, new_id, utcnow
from .errors import ApiError
from .identity_models import RefreshSession, User
from .operation_models import Order
from .push_models import Device, PushDelivery

router = APIRouter()
log = logging.getLogger("snackup.push")
TERMINAL = {"sent", "dead", "cancelled"}


class DeviceRegistration(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, hide_input_in_errors=True)
    token: str = Field(min_length=20, max_length=8192, json_schema_extra={"writeOnly": True})
    platform: Literal["android", "ios", "web"]
    provider: Literal["fcm", "apns", "webpush"]


class DeviceResponse(BaseModel):
    id: str
    platform: Literal["android", "ios", "web"]
    provider: Literal["fcm", "apns", "webpush"]
    lastActiveAt: str
    createdAt: str
    updatedAt: str


def _webpush_subscription(token, settings):
    """Only configured push services may receive credentials or encrypted data.

    Registrations cannot turn the worker into an arbitrary HTTP client. Hosts
    must match exactly (no suffix matching), and redirects are disabled on send.
    The endpoint cannot contain credentials, a custom port, query or fragment.
    """
    try:
        value = json.loads(token)
        if not isinstance(value, dict) or set(value) - {"endpoint", "keys", "expirationTime"}:
            raise ValueError
        endpoint, keys = value["endpoint"], value["keys"]
        if not isinstance(endpoint, str) or not isinstance(keys, dict) or set(keys) != {"auth", "p256dh"}:
            raise ValueError
        address = urlsplit(endpoint)
        allowed = {host.strip().lower() for host in settings.push_webpush_allowed_hosts.split(",") if host.strip()}
        if (address.scheme != "https" or address.hostname not in allowed or address.username or address.password
                or address.port not in {None, 443} or address.query or address.fragment
                or not address.path.startswith("/") or any(c.isspace() for c in endpoint)
                or not re.fullmatch(r"[a-z0-9.-]+", address.hostname or "")
                or re.fullmatch(r"[0-9.]+", address.hostname or "")):
            raise ValueError
        for name, expected in (("auth", 16), ("p256dh", 65)):
            encoded = keys[name]
            if not isinstance(encoded, str) or not re.fullmatch(r"[A-Za-z0-9_-]+={0,2}", encoded):
                raise ValueError
            decoded = base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4))
            if len(decoded) != expected or (name == "p256dh" and decoded[0] != 4):
                raise ValueError
            if name == "p256dh":
                from cryptography.hazmat.primitives.asymmetric import ec
                ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), decoded)
            keys[name] = base64.urlsafe_b64encode(decoded).decode().rstrip("=")
        # Ignore browser expiration metadata: it is not an authorization claim.
        endpoint = urlunsplit(("https", address.hostname, address.path, "", ""))
        return {"endpoint": endpoint, "keys": keys}
    except (ValueError, KeyError, TypeError, AttributeError):
        raise ApiError(422, "INVALID_DEVICE_TOKEN", "La suscripción de notificaciones no es válida.") from None


def canonical_token(payload, settings):
    if (payload.provider == "apns" and payload.platform != "ios") or (
            payload.provider == "webpush" and payload.platform != "web"):
        raise ApiError(422, "INVALID_DEVICE_PROVIDER", "El proveedor no corresponde a la plataforma.")
    token = payload.token
    if payload.provider == "webpush":
        return json.dumps(_webpush_subscription(token, settings), sort_keys=True, separators=(",", ":"))
    if payload.provider == "apns":
        if not re.fullmatch(r"[0-9a-fA-F]{32,512}", token) or len(token) % 2:
            raise ApiError(422, "INVALID_DEVICE_TOKEN", "El token del dispositivo no es válido.")
        return token.lower()
    if len(token) > 4096 or any(ord(c) < 33 or ord(c) > 126 for c in token):
        raise ApiError(422, "INVALID_DEVICE_TOKEN", "El token del dispositivo no es válido.")
    return token


def _delete_devices(db, devices, reason="DEVICE_REMOVED"):
    ids = [device.id for device in devices]
    if not ids:
        return
    db.execute(update(RefreshSession).where(RefreshSession.device_id.in_(ids)).values(device_id=None))
    db.execute(update(PushDelivery).where(PushDelivery.device_id.in_(ids),
                                          PushDelivery.state.not_in(TERMINAL))
               .values(state="cancelled", last_error=reason, lease_id=None, locked_until=None, updated_at=utcnow()))
    # Clear references explicitly for databases configured without FK cascades.
    db.execute(update(PushDelivery).where(PushDelivery.device_id.in_(ids)).values(device_id=None))
    for device in devices:
        db.delete(device)
    db.flush()


def detach_devices_for_families(db, family_ids, user_id=None):
    """Caller holds User's lock; an old family cannot delete a rebound token."""
    families = list(family_ids)
    if not families:
        return
    query = select(Device).where(Device.session_family_id.in_(families))
    if user_id is not None:
        query = query.where(Device.user_id == user_id)
    _delete_devices(db, db.scalars(query.with_for_update()).all(), "SESSION_REVOKED")


def _device_json(device):
    return {"id": device.id, "platform": device.platform, "provider": device.provider,
            "lastActiveAt": as_utc(device.last_active_at).isoformat(),
            "createdAt": as_utc(device.created_at).isoformat(), "updatedAt": as_utc(device.updated_at).isoformat()}


@router.post("/users/me/devices", status_code=201, response_model=DeviceResponse,
             responses={200: {"model": DeviceResponse}}, tags=["V3 · Dispositivos"])
def register_device(payload: DeviceRegistration, request: Request, response: Response,
                    user: User = Depends(request_user), db: Session = Depends(get_db, scope="function")):
    token = canonical_token(payload, request.app.state.settings)
    # A Web Push installation cannot evade ownership by supplying different
    # encryption keys for an endpoint already registered by someone else.
    identity = json.loads(token)["endpoint"] if payload.provider == "webpush" else token
    digest = hashlib.sha256(identity.encode()).hexdigest()
    # The User lock also serializes logout, refresh and same-account rebinds.
    user = db.scalar(select(User).where(User.id == user.id).with_for_update().execution_options(populate_existing=True))
    bearer = request.headers["authorization"].partition(" ")[2]
    verify_access_token(bearer, db, request.app.state.settings)
    claims = jwt.decode(bearer, options={"verify_signature": False})  # Already verified immediately above.
    session = db.scalar(select(RefreshSession).where(RefreshSession.id == claims["sid"])
                        .with_for_update().execution_options(populate_existing=True))
    if (session is None or session.user_id != user.id or session.revoked_at is not None
            or as_utc(session.expires_at) <= utcnow() or session.auth_version != user.auth_version):
        raise ApiError(401, "UNAUTHENTICATED")
    device = db.scalar(select(Device).where(Device.token_hash == digest).with_for_update())
    if device is not None and device.user_id != user.id:
        # Knowing another installation's token is not evidence of ownership.
        raise ApiError(409, "DEVICE_TOKEN_IN_USE", "La suscripción ya está registrada. Elimina su registro anterior.")
    if device is None and db.scalar(select(func.count()).select_from(Device).where(Device.user_id == user.id)) >= 20:
        raise ApiError(409, "DEVICE_LIMIT", "Elimina un dispositivo anterior antes de registrar otro.")
    replaced = db.scalars(select(Device).where(Device.user_id == user.id,
                         Device.session_family_id == session.family_id,
                         Device.token_hash != digest).with_for_update()).all()
    _delete_devices(db, replaced, "TOKEN_REPLACED")
    now = utcnow()
    if device is None:
        device = Device(user_id=user.id, token=token, token_hash=digest, platform=payload.platform,
                        provider=payload.provider, session_family_id=session.family_id,
                        last_active_at=now, created_at=now, updated_at=now)
        db.add(device)
        db.flush()
    else:
        # A newer login on the same installation supersedes the previous family.
        db.execute(update(RefreshSession).where(RefreshSession.device_id == device.id,
                                              RefreshSession.family_id != session.family_id).values(device_id=None))
        device.platform, device.provider = payload.platform, payload.provider
        device.token = token
        device.session_family_id, device.last_active_at, device.updated_at = session.family_id, now, now
        response.status_code = 200
    db.execute(update(RefreshSession).where(RefreshSession.user_id == user.id,
                                          RefreshSession.family_id == session.family_id).values(device_id=device.id))
    return _device_json(device)


@router.delete("/users/me/devices/{deviceId}", status_code=204, tags=["V3 · Dispositivos"])
def delete_device(deviceId: str, request: Request, user: User = Depends(request_user), db: Session = Depends(get_db, scope="function")):
    user = db.scalar(select(User).where(User.id == user.id).with_for_update().execution_options(populate_existing=True))
    verify_access_token(request.headers["authorization"].partition(" ")[2], db, request.app.state.settings)
    device = db.scalar(select(Device).where(Device.id == deviceId, Device.user_id == user.id).with_for_update())
    if device is None:
        raise ApiError(404, "NOT_FOUND", "No se encontró el dispositivo.")
    _delete_devices(db, [device])
    return Response(status_code=204)


def enqueue_outbox_push(db, row):
    """Run in the outbox publication transaction, before marking it published."""
    if row.event_type not in {"order.created", "order.updated"} or not isinstance(row.data, dict):
        return
    data = row.data
    if data.get("change") == "rating":
        return
    order = db.get(Order, data.get("id")) if isinstance(data.get("id"), str) else None
    if order is None or data.get("businessId") != order.business_id:
        return
    state = data.get("status")
    kitchen_topic = f"business:{order.business_id}:orders"
    user_topic = f"user:{order.student_id}:orders"
    recipients, title = [], None
    if row.event_type == "order.created" and row.topic == kitchen_topic:
        recipients = db.scalars(select(User.id).where(User.role == "business", User.business_id == order.business_id,
                                                      User.is_active.is_(True), User.approval_status == "approved")).all()
        title = f"Nuevo pedido #{order.order_number}"
    elif row.event_type == "order.updated":
        if state == "cancelled":
            actor = order.cancelled_by_role or ("ALUMNO" if order.cancelled_by == order.student_id else "COCINA")
            if actor in {"ALUMNO", "user"} and row.topic == kitchen_topic:
                recipients = db.scalars(select(User.id).where(User.role == "business", User.business_id == order.business_id,
                                                              User.is_active.is_(True), User.approval_status == "approved")).all()
            elif actor in {"COCINA", "business", "admin", "ADMIN"} and row.topic == user_topic:
                recipients = [order.student_id]
            title = "Pedido cancelado"
        elif row.topic == user_topic and state in {"accepted", "ready", "completed"}:
            recipients = [order.student_id]
            title = {"accepted": "Pedido confirmado", "ready": "¡Tu pedido está listo!",
                     "completed": "¿Cómo estuvo tu pedido?"}[state]
    if not title or not recipients:
        return
    # Explicit allowlist. No names, matrícula, pickup code, notes or payment data.
    payload = {"title": title, "body": "Abre SnackUP para consultar tu pedido.", "data": {
        "eventId": row.event_id, "type": row.event_type, "orderId": order.id,
        "businessId": order.business_id, "status": state, "version": data.get("version"),
        "action": "review" if state == "completed" else "order"}}
    for device in db.scalars(select(Device).where(Device.user_id.in_(recipients))):
        existing = db.scalar(select(PushDelivery.id).where(PushDelivery.outbox_event_id == row.id,
                                                          PushDelivery.device_id == device.id))
        if existing is None:
            db.add(PushDelivery(outbox_event_id=row.id, event_id=row.event_id, device_id=device.id,
                                user_id=device.user_id, payload=payload))


@dataclass(frozen=True)
class PushResult:
    kind: str  # accepted, retry, invalid, unconfigured, permanent
    code: str = ""
    message_id: str | None = None
    retry_after: float = 0


def _retry_after(headers):
    raw = headers.get("retry-after", "")
    try:
        return max(0, min(float(raw), 86400))
    except (TypeError, ValueError):
        try:
            return max(0, min((as_utc(parsedate_to_datetime(raw)) - utcnow()).total_seconds(), 86400))
        except (TypeError, ValueError, OverflowError):
            return 0


def _provider_error(status, headers, invalid=False):
    if invalid:
        return PushResult("invalid", "TOKEN_INVALID")
    if status in {401, 403}:
        return PushResult("unconfigured", "PROVIDER_AUTH_FAILED")
    if status == 429 or status >= 500:
        return PushResult("retry", "PROVIDER_TEMPORARY", retry_after=max(60 if status == 429 else 0, _retry_after(headers)))
    return PushResult("permanent", "PROVIDER_REJECTED")


class FCMProvider:
    def __init__(self, settings):
        self.settings, self.credentials, self.guard = settings, None, threading.Lock()

    def configured(self):
        return bool(self.settings.push_fcm_credentials_file and
                    re.fullmatch(r"[a-z0-9][a-z0-9-]{3,62}", self.settings.push_fcm_project_id))

    def send(self, token, payload):
        settings = self.settings
        if not self.configured():
            return PushResult("unconfigured", "FCM_NOT_CONFIGURED")
        from google.oauth2 import service_account
        from google.auth.transport.requests import Request as GoogleRequest
        import requests
        try:
            with self.guard:
                if self.credentials is None:
                    info = json.loads(settings.push_fcm_credentials_file.read_text())
                    if info.get("token_uri") != "https://oauth2.googleapis.com/token" or info.get("type") != "service_account":
                        return PushResult("unconfigured", "FCM_INVALID_CONFIGURATION")
                    self.credentials = service_account.Credentials.from_service_account_info(
                        info, scopes=["https://www.googleapis.com/auth/firebase.messaging"])
                if not self.credentials.valid:
                    class BoundedSession(requests.Session):
                        def request(self, method, url, **kwargs):
                            kwargs.update(timeout=settings.push_http_timeout_seconds, allow_redirects=False)
                            return super().request(method, url, **kwargs)
                    with BoundedSession() as session:
                        self.credentials.refresh(GoogleRequest(session=session))
                access = self.credentials.token
            with httpx.Client(timeout=settings.push_http_timeout_seconds, follow_redirects=False) as client:
                result = client.post(f"https://fcm.googleapis.com/v1/projects/{settings.push_fcm_project_id}/messages:send",
                    headers={"Authorization": "Bearer " + access}, json={"message": {"token": token,
                    "notification": {"title": payload["title"], "body": payload["body"]},
                    "data": {key: str(value) for key, value in payload["data"].items() if value is not None}}})
            if result.status_code == 200:
                return PushResult("accepted", message_id=result.json().get("name"))
            details = result.json().get("error", {}).get("details", []) if result.headers.get("content-type", "").startswith("application/json") else []
            invalid = any(isinstance(detail, dict) and detail.get("errorCode") == "UNREGISTERED" for detail in details)
            return _provider_error(result.status_code, result.headers, invalid)
        except (OSError, ValueError, TypeError, KeyError):
            return PushResult("unconfigured", "FCM_INVALID_CONFIGURATION")
        except Exception:
            # Provider exceptions can contain the complete token/credential URL.
            return PushResult("retry", "FCM_TRANSPORT_FAILED")


class APNSProvider:
    def __init__(self, settings):
        self.settings = settings
        self.cached_token, self.issued_at = None, 0
        self.guard = threading.Lock()

    def configured(self):
        settings = self.settings
        return bool(settings.push_apns_key_file and re.fullmatch(r"[A-Za-z0-9]{8,32}", settings.push_apns_key_id)
                    and re.fullmatch(r"[A-Za-z0-9]{8,32}", settings.push_apns_team_id)
                    and re.fullmatch(r"[A-Za-z0-9.-]{3,255}", settings.push_apns_topic))

    def send(self, token, payload):
        settings = self.settings
        if not self.configured():
            return PushResult("unconfigured", "APNS_NOT_CONFIGURED")
        try:
            with self.guard:
                now = int(time.time())
                if self.cached_token is None or now - self.issued_at > 2400:
                    self.cached_token = jwt.encode({"iss": settings.push_apns_team_id, "iat": now},
                        settings.push_apns_key_file.read_text(), algorithm="ES256", headers={"kid": settings.push_apns_key_id})
                    self.issued_at = now
                auth = self.cached_token
            host = "api.sandbox.push.apple.com" if settings.push_apns_sandbox else "api.push.apple.com"
            with httpx.Client(http2=True, timeout=settings.push_http_timeout_seconds, follow_redirects=False) as client:
                result = client.post(f"https://{host}/3/device/{token}", headers={
                    "authorization": "bearer " + auth, "apns-topic": settings.push_apns_topic,
                    "apns-push-type": "alert", "apns-priority": "10", "apns-expiration": str(int(time.time()) + 3600)},
                    json={"aps": {"alert": {"title": payload["title"], "body": payload["body"]}, "sound": "default"},
                          "data": payload["data"]})
            if result.status_code == 200:
                return PushResult("accepted", message_id=result.headers.get("apns-id"))
            reason = result.json().get("reason") if result.content else None
            return _provider_error(result.status_code, result.headers,
                                   result.status_code == 410 or reason in {"BadDeviceToken", "Unregistered"})
        except (OSError, ValueError, TypeError, jwt.PyJWTError):
            return PushResult("unconfigured", "APNS_INVALID_CONFIGURATION")
        except Exception:
            return PushResult("retry", "APNS_TRANSPORT_FAILED")


class WebPushProvider:
    def __init__(self, settings):
        self.settings = settings

    def configured(self):
        return bool(self.settings.push_webpush_private_key_file and
                    self.settings.push_webpush_subject.startswith(("mailto:", "https://")))

    def send(self, token, payload):
        settings = self.settings
        if not self.configured():
            return PushResult("unconfigured", "WEBPUSH_NOT_CONFIGURED")
        try:
            subscription = _webpush_subscription(token, settings)
        except ApiError:
            return PushResult("invalid", "TOKEN_INVALID")
        import requests
        from pywebpush import WebPushException, webpush
        class BoundedSession(requests.Session):
            def request(self, method, url, **kwargs):
                kwargs.update(allow_redirects=False, timeout=settings.push_http_timeout_seconds)
                return super().request(method, url, **kwargs)
        try:
            with BoundedSession() as session:
                result = webpush(subscription, json.dumps(payload, separators=(",", ":")),
                    vapid_private_key=str(settings.push_webpush_private_key_file),
                    vapid_claims={"sub": settings.push_webpush_subject}, ttl=3600,
                    timeout=settings.push_http_timeout_seconds, requests_session=session)
            if 200 <= result.status_code < 300:
                return PushResult("accepted")
            return _provider_error(result.status_code, result.headers, result.status_code in {404, 410})
        except WebPushException as error:
            if error.response is not None:
                return _provider_error(error.response.status_code, error.response.headers,
                                       error.response.status_code in {404, 410})
            return PushResult("permanent", "WEBPUSH_INVALID_SUBSCRIPTION")
        except (OSError, ValueError, TypeError):
            return PushResult("unconfigured", "WEBPUSH_INVALID_CONFIGURATION")
        except Exception:
            return PushResult("retry", "WEBPUSH_TRANSPORT_FAILED")


class PushDispatcher:
    def __init__(self, app):
        self.app, self.settings, self.db = app, app.state.settings, app.state.db
        # Tests replace these adapters, not persistence or authorization logic.
        self.providers = {"fcm": FCMProvider(self.settings), "apns": APNSProvider(self.settings),
                          "webpush": WebPushProvider(self.settings)}
        self.task = None

    def _claim(self):
        now = utcnow()
        with self.db.sessions.begin() as db:
            jobs = db.scalars(select(PushDelivery).where(or_(
                and_(PushDelivery.state.in_(["pending", "retry", "unconfigured"]), PushDelivery.next_attempt_at <= now),
                and_(PushDelivery.state == "sending", PushDelivery.locked_until <= now)))
                .order_by(PushDelivery.next_attempt_at, PushDelivery.id).limit(self.settings.push_batch_size)
                .with_for_update(skip_locked=True)).all()
            claims = []
            for job in jobs:
                job.state, job.lease_id = "sending", new_id()
                job.locked_until = now + timedelta(seconds=self.settings.push_delivery_lease_seconds)
                claims.append((job.id, job.lease_id))
            return claims

    def _prepare(self, identity, lease):
        with self.db.sessions.begin() as db:
            job = db.get(PushDelivery, identity)
            if job is None or job.state != "sending" or job.lease_id != lease:
                return None
            device = db.get(Device, job.device_id) if job.device_id else None
            user = db.get(User, job.user_id)
            try:
                if user is None or device is None or device.user_id != user.id:
                    raise ApiError(401, "DEVICE_REMOVED")
                ensure_account(user, db)
                active = db.scalar(select(RefreshSession.id).where(RefreshSession.user_id == user.id,
                    RefreshSession.family_id == device.session_family_id, RefreshSession.device_id == device.id,
                    RefreshSession.revoked_at.is_(None), RefreshSession.expires_at > utcnow(),
                    RefreshSession.auth_version == user.auth_version).limit(1))
                if active is None:
                    raise ApiError(401, "SESSION_REVOKED")
                order = db.get(Order, job.payload["data"]["orderId"])
                if order is None:
                    raise ApiError(404, "ORDER_REMOVED")
                if user.role == "user":
                    if order.student_id != user.id:
                        raise ApiError(403, "ACCESS_REVOKED")
                elif user.role != "business" or order.business_id != user.business_id:
                    raise ApiError(403, "ACCESS_REVOKED")
                # A delayed 'ready' or 'new order' alert must not outlive a later
                # state. The event still exists for audit/realtime deduplication.
                if order.status != job.payload["data"]["status"]:
                    raise ApiError(409, "ORDER_SUPERSEDED")
                return device.provider, device.token, job.payload
            except ApiError as error:
                job.state, job.last_error, job.lease_id, job.locked_until = "cancelled", error.code, None, None
                return None

    def _finish(self, identity, lease, result):
        with self.db.sessions.begin() as db:
            # Invalid tokens need User -> Device -> job order, matching logout.
            snapshot = db.get(PushDelivery, identity)
            if snapshot is None:
                return
            db.scalar(select(User).where(User.id == snapshot.user_id).with_for_update())
            job = db.scalar(select(PushDelivery).where(PushDelivery.id == identity).with_for_update()
                            .execution_options(populate_existing=True))
            if job is None or job.state != "sending" or job.lease_id != lease:
                return
            now = utcnow()
            job.locked_until, job.lease_id, job.updated_at = None, None, now
            # Fixed internal error codes only; never persist provider response bodies.
            job.last_error = result.code if re.fullmatch(r"[A-Z0-9_]{0,80}", result.code) else "PROVIDER_ERROR"
            if result.kind == "unconfigured":
                job.state = "unconfigured"
                job.next_attempt_at = now + timedelta(seconds=self.settings.push_unconfigured_retry_seconds)
                return
            if result.kind == "accepted":
                job.state, job.sent_at, job.last_error = "sent", now, None
                job.provider_message_id = (result.message_id or "")[:512] or None
            elif result.kind == "invalid":
                job.state = "dead"
                device = db.get(Device, job.device_id) if job.device_id else None
                if device is not None:
                    _delete_devices(db, [device], "TOKEN_INVALID")
            elif result.kind == "permanent" or job.attempts >= self.settings.push_max_attempts:
                job.state = "dead"
            else:
                job.state = "retry"
                backoff = min(3600, self.settings.push_retry_base_seconds * 2 ** min(job.attempts - 1, 10))
                job.next_attempt_at = now + timedelta(seconds=max(result.retry_after, backoff + random.uniform(0, backoff / 4)))

    def _record_attempt(self, identity, lease):
        # Persist intent before the network call. A worker crash may make the
        # provider's outcome unknown; the next lease still counts that attempt.
        with self.db.sessions.begin() as db:
            job = db.scalar(select(PushDelivery).where(PushDelivery.id == identity).with_for_update())
            if job is None or job.state != "sending" or job.lease_id != lease:
                return False
            if job.attempts >= self.settings.push_max_attempts:
                job.state, job.last_error, job.lease_id, job.locked_until = "dead", "ATTEMPTS_EXHAUSTED", None, None
                return False
            job.attempts += 1
            job.locked_until = utcnow() + timedelta(seconds=self.settings.push_delivery_lease_seconds)
            return True

    async def _deliver(self, identity, lease):
        prepared = await asyncio.to_thread(self._prepare, identity, lease)
        if prepared is None:
            return
        provider, token, payload = prepared
        adapter = self.providers.get(provider)
        configured = adapter is not None and (not hasattr(adapter, "configured") or adapter.configured())
        if not self.settings.push_enabled or not configured:
            result = PushResult("unconfigured", "PUSH_DISABLED" if not self.settings.push_enabled else "PROVIDER_NOT_CONFIGURED")
        else:
            if not await asyncio.to_thread(self._record_attempt, identity, lease):
                return
            try:
                # Each adapter imposes HTTP timeouts. The outer deadline protects
                # the lease from a broken adapter, including test/deployment hooks.
                result = await asyncio.wait_for(asyncio.to_thread(self.providers[provider].send, token, payload),
                    timeout=self.settings.push_delivery_lease_seconds * 0.8)
                if not isinstance(result, PushResult):
                    result = PushResult("retry", "PROVIDER_INVALID_RESULT")
            except asyncio.CancelledError:
                raise
            except Exception:
                result = PushResult("retry", "PROVIDER_TRANSPORT_FAILED")
        await asyncio.to_thread(self._finish, identity, lease, result)

    async def dispatch_once(self):
        claims = await asyncio.to_thread(self._claim)
        semaphore = asyncio.Semaphore(min(8, self.settings.push_batch_size))

        async def deliver_bounded(identity, lease):
            async with semaphore:
                await self._deliver(identity, lease)

        await asyncio.gather(*(deliver_bounded(identity, lease) for identity, lease in claims))
        return len(claims)

    async def _loop(self):
        while True:
            claimed = 0
            try:
                claimed = await self.dispatch_once()
            except asyncio.CancelledError:
                raise
            except Exception:
                log.warning("Push dispatch unavailable; durable jobs retained")
            # Drain a backlog continuously with bounded parallel HTTP work.
            # The polling delay is for an idle/partial batch, not a throughput
            # limit of one batch every N seconds during busy service.
            await asyncio.sleep(0 if claimed == self.settings.push_batch_size else self.settings.push_poll_seconds)

    async def start(self):
        if self.task is None:
            self.task = asyncio.create_task(self._loop())

    async def stop(self):
        if self.task:
            self.task.cancel()
            await asyncio.gather(self.task, return_exceptions=True)
            self.task = None


def install_push(app):
    app.state.push = PushDispatcher(app)
    return app.state.push
