"""Canonical V3 identity boundary; legacy SQL role names are never public DTOs.

Registration deliberately returns 202 until email ownership is proven. Native
clients explicitly send a refresh token; browsers use the HttpOnly cookie only.
"""
from datetime import timedelta
import secrets
from typing import Literal

from fastapi import APIRouter, Body, Depends, Request, Response
from fastapi.responses import HTMLResponse, JSONResponse
import jwt
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .auth import (JWT_AUDIENCE, JWT_ISSUER, PASSWORDS, REFRESH_COOKIE, as_utc,
                   current_user, ensure_account, hash_password, password_matches,
                   require_origin, revoke_user_sessions, token_hash)
from .common import iso, require, version_check
from .db import get_db, new_id, utcnow
from .errors import ApiError
from .identity import (_clear_cookie, _consume_token, _cookie, _mail_token,
                       normalize_email, verification_page)
from .identity_models import (AcademicRecord, AccessRequest, RefreshSession, User,
                              VerificationToken, audit_event)
from .mailer import mail_available

router = APIRouter(tags=["V3 · Identidad"])
ROLE_TO_API = {"user": "ALUMNO", "business": "COCINA", "admin": "ADMIN"}


class InputModel(BaseModel):
    model_config = ConfigDict(extra="forbid", hide_input_in_errors=True)


class RegisterInput(InputModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=12, max_length=128, json_schema_extra={"writeOnly": True})
    displayName: str = Field(min_length=1, max_length=160)
    numeroDeControl: str = Field(min_length=1, max_length=50)


class LoginInput(InputModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=1, max_length=128, json_schema_extra={"writeOnly": True})


class RefreshInput(InputModel):
    refreshToken: str | None = Field(default=None, min_length=20, max_length=256,
                                    json_schema_extra={"writeOnly": True})


class EmailInput(InputModel):
    email: str = Field(min_length=3, max_length=254)


class VerifyInput(InputModel):
    token: str = Field(min_length=20, max_length=256, json_schema_extra={"writeOnly": True})


class ResetInput(VerifyInput):
    newPassword: str = Field(min_length=12, max_length=128, json_schema_extra={"writeOnly": True})


class ProfilePatch(InputModel):
    avatarUrl: str | None = Field(max_length=1000)
    expectedVersion: int = Field(ge=1, strict=True)


class AppUserResponse(BaseModel):
    id: str
    email: str
    displayName: str
    role: Literal["ALUMNO", "COCINA", "ADMIN"]
    businessId: str | None
    numeroDeControl: str | None
    avatarUrl: str | None
    createdAt: str
    lastLoginAt: str | None
    updatedAt: str
    version: int
    isActive: bool
    emailVerified: bool
    institutionalVerifiedAt: str | None


class TokensResponse(BaseModel):
    accessToken: str
    accessTokenExpiresAt: str
    refreshToken: str | None = None
    refreshTokenExpiresAt: str


class LoginResponse(BaseModel):
    user: AppUserResponse
    tokens: TokensResponse


class RefreshResponse(BaseModel):
    tokens: TokensResponse


class ReceivedResponse(BaseModel):
    status: Literal["received"] = "received"


class OptionsResponse(BaseModel):
    passwordLogin: bool
    selfRegistration: bool
    googleEnabled: bool


def serialize_v3_user(user: User, db: Session) -> dict:
    require(user.role in ROLE_TO_API, 409, "ACCOUNT_NOT_READY", "La cuenta aún no tiene un rol autorizado.")
    control = user.numero_de_control
    if user.role == "user" and control is None:
        control = db.scalar(select(AcademicRecord.institutional_id).where(
            AcademicRecord.email == user.email, AcademicRecord.kind == "student"))
    return {
        "id": user.id, "email": user.email, "displayName": user.display_name,
        "role": ROLE_TO_API[user.role], "businessId": user.business_id if user.role == "business" else None,
        "numeroDeControl": control if user.role == "user" else None,
        "avatarUrl": user.avatar_url, "createdAt": iso(user.created_at),
        "lastLoginAt": iso(user.last_login_at), "updatedAt": iso(user.updated_at),
        "version": user.version, "isActive": user.is_active,
        "emailVerified": user.email_verified, "institutionalVerifiedAt": iso(user.institutional_verified_at),
    }


def _is_web(request: Request) -> bool:
    if "origin" not in request.headers:
        return False
    require_origin(request)
    return True


def _refresh_value(request: Request, data: RefreshInput | None, *, optional=False) -> str | None:
    data = data or RefreshInput()
    if _is_web(request):
        require(data.refreshToken is None, 422, "COOKIE_REFRESH_REQUIRED", "El navegador renueva mediante cookie.")
        raw = request.cookies.get(REFRESH_COOKIE)
    else:
        # A browser cookie without Origin must not be interpreted as native auth.
        raw = data.refreshToken
        if not raw and request.cookies.get(REFRESH_COOKIE):
            raise ApiError(403, "ORIGIN_NOT_ALLOWED", "El origen de la solicitud no está permitido.")
    if not optional:
        require(bool(raw), 401, "UNAUTHENTICATED", "La sesión no es válida.")
    return raw


def _issue_v3_session(db: Session, user: User, request: Request, response: Response,
                      previous: RefreshSession | None = None) -> dict:
    settings = request.app.state.settings
    now = utcnow()
    raw = secrets.token_urlsafe(48)
    session = RefreshSession(id=new_id(), user_id=user.id,
                             family_id=previous.family_id if previous else new_id(),
                             token_hash=token_hash(raw), auth_version=user.auth_version,
                             device_id=previous.device_id if previous else None,
                             expires_at=now + timedelta(days=settings.refresh_days))
    db.add(session)
    db.flush()
    if previous is not None:
        previous.rotated_at = now
        previous.replaced_by_id = session.id
    expiry = now + timedelta(minutes=settings.access_token_minutes)
    claims = {"sub": user.id, "sid": session.id, "ver": user.auth_version,
              "role": ROLE_TO_API[user.role], "iat": now, "exp": expiry,
              "iss": JWT_ISSUER, "aud": JWT_AUDIENCE}
    if user.role == "business":
        claims["bid"] = user.business_id
    access = jwt.encode(claims, settings.secret_key, algorithm="HS256")
    tokens = {"accessToken": access, "accessTokenExpiresAt": iso(expiry),
              "refreshTokenExpiresAt": iso(session.expires_at)}
    if _is_web(request):
        _cookie(response, raw, settings, session.expires_at)
    else:
        tokens["refreshToken"] = raw
    response.headers["Cache-Control"] = "no-store"
    return tokens


def _student_record(db, settings, email, control):
    domains = {x.strip().lower() for x in settings.student_email_domains.split(",") if x.strip()}
    require(bool(domains), 503, "INSTITUTION_NOT_CONFIGURED", "Falta configurar los dominios institucionales.")
    record = db.scalar(select(AcademicRecord).where(AcademicRecord.email == email)
                       .execution_options(populate_existing=True))
    if (email.rsplit("@", 1)[1] not in domains or record is None or record.kind != "student"
            or not record.is_active or record.institutional_id != control):
        return None
    return record


@router.get("/auth/options", response_model=OptionsResponse)
def options(request: Request):
    return {"passwordLogin": True, "selfRegistration": mail_available(request.app.state.settings), "googleEnabled": False}


@router.post("/auth/register", status_code=202, response_model=ReceivedResponse,
             description="Solo ALUMNO. Acuse genérico sin sesión; requiere padrón y confirmación de correo.")
def register(request: Request, data: RegisterInput, db: Session = Depends(get_db, scope="function")):
    _is_web(request)
    settings = request.app.state.settings
    require(mail_available(settings), 503, "EMAIL_UNAVAILABLE", "El registro requiere envío de correo configurado.")
    email = normalize_email(data.email)
    require(bool(data.displayName.strip()) and bool(data.numeroDeControl.strip()))
    encoded = hash_password(data.password)
    # Serialize with account changes/verification before reading the roster.
    user = db.scalar(select(User).where(User.email == email).with_for_update()
                     .execution_options(populate_existing=True))
    record = _student_record(db, settings, email, data.numeroDeControl.strip())
    if record is None:
        return {"status": "received"}
    recoverable = user is not None and user.role == "pending" and not user.email_verified and not user.is_active
    if user is not None and not recoverable:
        return {"status": "received"}
    registration_data = {"kind": "student_registration", "recordId": record.id,
                         "numeroDeControl": record.institutional_id}
    if recoverable:
        # Do not mutate an existing account's credentials or role until the
        # one-use link proves email ownership. A forged request cannot seize it.
        registration_data["passwordHash"] = encoded
    try:
        with db.begin_nested():
            if user is None:
                user = User(id=new_id(), email=email, display_name=record.display_name, password_hash=encoded,
                            role="user", is_master=False, is_active=True, approval_status="approved",
                            email_verified=False, numero_de_control=record.institutional_id)
                db.add(user)
                db.flush()
            _mail_token(db, user, settings, "verify", getattr(request.app.state, "mailer", None),
                        registration_data=registration_data)
    except IntegrityError:
        if db.scalar(select(User.id).where(User.email == email)) is None:
            raise
    return {"status": "received"}


@router.post("/auth/login", response_model=LoginResponse, response_model_exclude_unset=True)
def login(request: Request, response: Response, data: LoginInput,
          db: Session = Depends(get_db, scope="function")):
    _is_web(request)
    email = normalize_email(data.email)
    user = db.scalar(select(User).where(User.email == email).with_for_update()
                     .execution_options(populate_existing=True))
    if not password_matches(data.password, user.password_hash if user else None):
        raise ApiError(401, "INVALID_CREDENTIALS", "Correo o contraseña incorrectos.")
    ensure_account(user, db)
    if PASSWORDS.check_needs_rehash(user.password_hash):
        user.password_hash = hash_password(data.password)
    user.last_login_at = utcnow()
    db.flush()
    return {"user": serialize_v3_user(user, db), "tokens": _issue_v3_session(db, user, request, response)}


@router.post("/auth/refresh", response_model=RefreshResponse, response_model_exclude_unset=True)
def refresh(request: Request, response: Response, data: RefreshInput | None = Body(default=None),
            db: Session = Depends(get_db, scope="function")):
    raw = _refresh_value(request, data)
    initial = db.scalar(select(RefreshSession).where(RefreshSession.token_hash == token_hash(raw)))
    require(initial is not None, 401, "UNAUTHENTICATED", "La sesión no es válida.")
    user = db.scalar(select(User).where(User.id == initial.user_id).with_for_update()
                     .execution_options(populate_existing=True))
    session = db.scalar(select(RefreshSession).where(RefreshSession.id == initial.id).with_for_update()
                        .execution_options(populate_existing=True))
    if session.rotated_at is not None:
        db.execute(update(RefreshSession).where(RefreshSession.family_id == session.family_id).values(revoked_at=utcnow()))
        from .push import detach_devices_for_families
        detach_devices_for_families(db, {session.family_id}, user_id=user.id if user is not None else None)
        failure = JSONResponse({"error": {"code": "SESSION_REPLAY", "message": "La sesión fue revocada. Inicia sesión nuevamente."}}, status_code=401)
        _clear_cookie(failure, request.app.state.settings)
        return failure  # Commit revocation even though the response is an error.
    require(user is not None and session.revoked_at is None and as_utc(session.expires_at) > utcnow()
            and session.auth_version == user.auth_version, 401, "UNAUTHENTICATED", "La sesión fue revocada.")
    ensure_account(user, db)
    return {"tokens": _issue_v3_session(db, user, request, response, previous=session)}


@router.post("/auth/logout", status_code=204)
def logout(request: Request, data: RefreshInput | None = Body(default=None),
           db: Session = Depends(get_db, scope="function")):
    raw = _refresh_value(request, data, optional=True)
    families = set()
    if raw:
        session = db.scalar(select(RefreshSession).where(RefreshSession.token_hash == token_hash(raw)))
        if session is not None:
            families.add(session.family_id)
    authorization = request.headers.get("authorization", "")
    scheme, _, access = authorization.partition(" ")
    if scheme.lower() == "bearer" and access:
        try:
            claims = jwt.decode(access, request.app.state.settings.secret_key, algorithms=["HS256"],
                                issuer=JWT_ISSUER, audience=JWT_AUDIENCE,
                                options={"verify_exp": False, "require": ["sid", "sub", "iss", "aud"]})
            session = db.get(RefreshSession, claims["sid"])
            if session is not None and session.user_id == claims["sub"]:
                families.add(session.family_id)
        except (jwt.InvalidTokenError, TypeError):
            pass
    if families:
        user_ids = select(RefreshSession.user_id).where(RefreshSession.family_id.in_(families)).distinct()
        list(db.scalars(select(User).where(User.id.in_(user_ids)).order_by(User.id).with_for_update()))
        db.execute(update(RefreshSession).where(RefreshSession.family_id.in_(families)).values(revoked_at=utcnow()))
        from .push import detach_devices_for_families
        detach_devices_for_families(db, families)
    response = Response(status_code=204)
    _clear_cookie(response, request.app.state.settings)
    return response


@router.get("/users/me", response_model=AppUserResponse)
def profile(user: User = Depends(current_user), db: Session = Depends(get_db, scope="function")):
    return serialize_v3_user(user, db)


@router.patch("/users/me", response_model=AppUserResponse,
              description="Vincula o retira un avatar propio; no cambia rol, correo ni datos del padrón.")
def update_profile(request: Request, data: ProfilePatch, user: User = Depends(current_user),
                   db: Session = Depends(get_db, scope="function")):
    user = db.scalar(select(User).where(User.id == user.id).with_for_update()
                     .execution_options(populate_existing=True))
    user = current_user(request, db)
    version_check(user, data.expectedVersion)
    from .v3_media import owned_media
    owned_media(db, user, data.avatarUrl, request.app.state.settings, purpose="avatar")
    user.avatar_url = data.avatarUrl
    user.version += 1
    user.updated_at = utcnow()
    db.flush()
    return serialize_v3_user(user, db)


@router.post("/auth/forgot-password", status_code=204)
def forgot_password(request: Request, data: EmailInput, db: Session = Depends(get_db, scope="function")):
    _is_web(request)
    settings = request.app.state.settings
    require(mail_available(settings), 503, "EMAIL_UNAVAILABLE", "La recuperación requiere envío de correo configurado.")
    email = normalize_email(data.email)
    user = db.scalar(select(User).where(User.email == email).with_for_update())
    if user is not None and user.approval_status != "rejected":
        _mail_token(db, user, settings, "reset", getattr(request.app.state, "mailer", None))
    return Response(status_code=204)


@router.post("/auth/reset-password", status_code=204)
def reset_password(request: Request, data: ResetInput, db: Session = Depends(get_db, scope="function")):
    _is_web(request)
    _, user = _consume_token(db, data.token, "reset")
    user.password_hash = hash_password(data.newPassword)
    user.version += 1
    revoke_user_sessions(db, user)
    families = set(db.scalars(select(RefreshSession.family_id).where(RefreshSession.user_id == user.id)))
    from .push import detach_devices_for_families
    detach_devices_for_families(db, families, user_id=user.id)
    audit_event(db, user.id, "password.reset", "user", user.id)
    response = Response(status_code=204)
    _clear_cookie(response, request.app.state.settings)
    return response


@router.post("/auth/resend-verification", status_code=202, response_model=ReceivedResponse)
def resend(request: Request, data: EmailInput, db: Session = Depends(get_db, scope="function")):
    _is_web(request)
    settings = request.app.state.settings
    require(mail_available(settings), 503, "EMAIL_UNAVAILABLE", "El envío de correo aún no está configurado.")
    user = db.scalar(select(User).where(User.email == normalize_email(data.email)).with_for_update())
    if user is not None and not user.email_verified and user.approval_status != "rejected":
        previous = db.scalar(select(VerificationToken).where(VerificationToken.user_id == user.id,
                              VerificationToken.purpose == "verify", VerificationToken.used_at.is_(None))
                              .order_by(VerificationToken.created_at.desc()).limit(1))
        pending_data = previous.registration_data if previous else None
        _mail_token(db, user, settings, "verify", getattr(request.app.state, "mailer", None),
                    registration_data=pending_data)
    return {"status": "received"}


@router.post("/auth/verify-email", status_code=204)
def verify_email(request: Request, data: VerifyInput, db: Session = Depends(get_db, scope="function")):
    _is_web(request)
    token, user = _consume_token(db, data.token, "verify")
    metadata = token.registration_data
    if metadata and metadata.get("kind") == "student_registration":
        record = _student_record(db, request.app.state.settings, user.email, metadata["numeroDeControl"])
        require(record is not None and record.id == metadata.get("recordId"), 403, "ACCESS_REVOKED",
                "El padrón institucional no autoriza el acceso.")
        if user.role == "pending":
            require(not user.email_verified and not user.is_active and "passwordHash" in metadata,
                    409, "ACCOUNT_STATE_CHANGED", "La cuenta cambió. Inicia el registro nuevamente.")
            user.password_hash = metadata["passwordHash"]
            user.role, user.business_id, user.is_master = "user", None, False
            user.is_active, user.approval_status = True, "approved"
            access = db.scalar(select(AccessRequest).where(AccessRequest.user_id == user.id).with_for_update()
                               .execution_options(populate_existing=True))
            if access is not None and access.approval_status == "pending":
                access.approval_status = "rejected"
                access.note = "Sustituida por alta de alumno tras verificar propiedad del correo."
                access.decided_at = utcnow()
                access.version += 1
            revoke_user_sessions(db, user)
            audit_event(db, user.id, "student.pending_registration_recovered", "user", user.id)
        require(user.role == "user", 409, "ACCOUNT_STATE_CHANGED", "La cuenta cambió.")
        user.numero_de_control = record.institutional_id
        user.display_name = record.display_name
        user.institutional_verified_at = utcnow()
    user.email_verified = True
    user.version += 1
    access = db.scalar(select(AccessRequest).where(AccessRequest.user_id == user.id).with_for_update()
                       .execution_options(populate_existing=True))
    if access is not None:
        access.email_verified = True
        access.version += 1
    token.registration_data = None  # Remove the transient credential hash after use.
    return Response(status_code=204)


@router.get("/auth/verify-email", response_class=HTMLResponse, include_in_schema=False)
def verification_form():
    return verification_page()


@router.get("/auth/google/start")
def google_disabled():
    raise ApiError(503, "GOOGLE_DISABLED", "El acceso con Google no está habilitado.")
