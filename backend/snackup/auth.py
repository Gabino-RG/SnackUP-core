"""Password hashing, short lived access JWTs and current database authorization."""
import hashlib
from datetime import timezone

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from fastapi import Depends, Request, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from .db import get_db, utcnow
from .errors import ApiError
from .identity_models import AcademicRecord, RefreshSession, User

PASSWORDS = PasswordHasher(time_cost=2, memory_cost=19456, parallelism=1)
# An actual Argon2 operation also runs for missing accounts. This is not a login.
_DUMMY_HASH = PASSWORDS.hash("non-account-timing-equalizer")
JWT_ISSUER = "snackup-backend"
JWT_AUDIENCE = "snackup-api"
REFRESH_COOKIE = "snackup_refresh"
BEARER = HTTPBearer(auto_error=False, scheme_name="BearerAuth", bearerFormat="JWT")


def as_utc(value):
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def hash_password(password: str) -> str:
    if not isinstance(password, str) or not 12 <= len(password) <= 128:
        raise ApiError(422, "INVALID_PASSWORD", "La contraseña debe tener entre 12 y 128 caracteres.")
    return PASSWORDS.hash(password)


def password_matches(password: str, encoded: str | None) -> bool:
    if not isinstance(password, str) or len(password) > 128:
        return False
    try:
        return PASSWORDS.verify(encoded or _DUMMY_HASH, password) and encoded is not None
    except (VerificationError, InvalidHashError):
        return False


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def ensure_account_state(user, record, business_active=True):
    if user.approval_status == "pending":
        raise ApiError(403, "ACCESS_PENDING", "La solicitud está pendiente de autorización.")
    if user.approval_status == "rejected":
        raise ApiError(403, "ACCESS_REJECTED", "La solicitud no fue autorizada.")
    if not user.is_active or user.role not in ("admin", "business", "user"):
        raise ApiError(403, "ACCESS_REVOKED", "El acceso está suspendido.")
    if not user.email_verified:
        raise ApiError(403, "EMAIL_NOT_VERIFIED", "Confirma tu correo antes de iniciar sesión.")
    if user.role == "business" and not business_active:
        raise ApiError(403, "ACCESS_REVOKED", "El local asignado no está activo.")
    if record is not None and not record.is_active:
        raise ApiError(403, "ACCESS_REVOKED", "El padrón institucional no autoriza el acceso.")
    if user.role == "user" and (record is None or record.kind != "student"):
        raise ApiError(403, "ACCESS_REVOKED", "El padrón institucional no autoriza el acceso.")


def ensure_account(user: User, db: Session) -> None:
    record = db.scalar(select(AcademicRecord).where(AcademicRecord.email == user.email)
                       .execution_options(populate_existing=True))
    active = True
    if user.role == "business":
        from .operation_models import Business
        active = bool(db.scalar(select(Business.id).where(Business.id == user.business_id,
                                                          Business.is_active.is_(True))))
    ensure_account_state(user, record, active)


def decode_access_token(token, settings):
    try:
        claims = jwt.decode(token, settings.secret_key, algorithms=["HS256"],
                            issuer=JWT_ISSUER, audience=JWT_AUDIENCE,
                            options={"require": ["exp", "iat", "sub", "sid", "ver", "iss", "aud"]})
    except jwt.ExpiredSignatureError:
        raise ApiError(401, "TOKEN_EXPIRED", "La sesión requiere renovación.") from None
    except jwt.InvalidTokenError:
        raise ApiError(401, "UNAUTHENTICATED", "La sesión no es válida.") from None
    if not isinstance(claims.get("sid"), str) or not isinstance(claims.get("sub"), str):
        raise ApiError(401, "UNAUTHENTICATED", "La sesión no es válida.")
    return claims


def verify_access_tokens(tokens, db, settings):
    """Fresh authorization in one joined SELECT per batch, without a stale cache."""
    from .operation_models import Business
    claims, result = {}, {}
    for token in tokens:
        try:
            claims[token] = decode_access_token(token, settings)
        except ApiError:
            result[token] = None
    if not claims:
        return result
    rows = db.execute(select(RefreshSession, User, AcademicRecord, Business.is_active)
        .join(User, User.id == RefreshSession.user_id)
        .outerjoin(AcademicRecord, AcademicRecord.email == User.email)
        .outerjoin(Business, Business.id == User.business_id)
        .where(RefreshSession.id.in_({c['sid'] for c in claims.values()})))
    by_session = {session.id: (session, user, record, active) for session, user, record, active in rows}
    now = utcnow()
    for token, c in claims.items():
        value = by_session.get(c['sid'])
        result[token] = None
        if value is None:
            continue
        session, user, record, active = value
        if (user.id != c['sub'] or session.revoked_at is not None or as_utc(session.expires_at) <= now
                or c['ver'] != user.auth_version or session.auth_version != user.auth_version):
            continue
        try:
            ensure_account_state(user, record, active)
            result[token] = user
        except ApiError:
            pass
    return result

def verify_access_token(token: str, db: Session, settings) -> User:
    claims = decode_access_token(token, settings)
    sid = claims['sid']
    # A joined, fresh snapshot avoids three round trips per authenticated read.
    # populate_existing also refreshes objects loaded before a write-lock wait.
    from .operation_models import Business
    row = db.execute(select(RefreshSession, User, AcademicRecord, Business.is_active)
        .join(User, User.id == RefreshSession.user_id)
        .outerjoin(AcademicRecord, AcademicRecord.email == User.email)
        .outerjoin(Business, Business.id == User.business_id)
        .where(RefreshSession.id == sid, User.id == claims['sub'])
        .execution_options(populate_existing=True)).first()
    if row is None:
        raise ApiError(401, "UNAUTHENTICATED", "La sesión fue revocada.")
    session, user, record, active = row
    if (session.revoked_at is not None or as_utc(session.expires_at) <= utcnow() or
            claims.get("ver") != user.auth_version or session.auth_version != user.auth_version):
        raise ApiError(401, "UNAUTHENTICATED", "La sesión fue revocada.")
    ensure_account_state(user, record, active)
    return user


def current_user(request: Request, db: Session = Depends(get_db, scope="function"),
                 credentials: HTTPAuthorizationCredentials | None = Security(BEARER)) -> User:
    authorization = request.headers.get("authorization", "")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise ApiError(401, "UNAUTHENTICATED", "Inicia sesión para continuar.")
    return verify_access_token(token, db, request.app.state.settings)


def request_user(request: Request, db: Session = Depends(get_db, scope="function"),
                 credentials: HTTPAuthorizationCredentials | None = Security(BEARER)) -> User:
    """The dependency returns its connection before FastAPI schedules the handler.

    Objects stay attached (expire_on_commit=False). Write handlers still call
    current_user after their locks; that function never ends their transaction.
    """
    user = current_user(request, db, credentials)
    db.commit()
    return user


def login_user(db: Session, request: Request, email: str, password: str) -> User:
    user = db.scalar(select(User).where(User.email == email))
    snapshot = (user.id, user.password_hash, user.auth_version) if user else None
    db.commit()  # No connection or row lock during Argon2, including its queue.
    def verify():
        matched = password_matches(password, snapshot[1] if snapshot else None)
        replacement = (hash_password(password) if matched and PASSWORDS.check_needs_rehash(snapshot[1]) else None)
        return matched, replacement
    # Fixed hash threads also bound allocator arenas: a semaphore on FastAPI's
    # rotating worker threads allowed each thread to retain an Argon2 buffer.
    matched, replacement = request.app.state.password_executor.submit(verify).result()
    if not matched:
        raise ApiError(401, "INVALID_CREDENTIALS", "Correo o contraseña incorrectos.")
    user = db.scalar(select(User).where(User.id == snapshot[0]).with_for_update(key_share=True)
                     .execution_options(populate_existing=True))
    if user is None or (user.password_hash, user.auth_version) != snapshot[1:]:
        raise ApiError(401, "INVALID_CREDENTIALS", "Correo o contraseña incorrectos.")
    # Read related authorization AFTER a possible row-lock wait. Joining it
    # into the locking SELECT could retain a pre-wait PostgreSQL snapshot.
    ensure_account(user, db)
    if replacement:
        user.password_hash = replacement
    return user


def require_admin(user: User = Depends(request_user)) -> User:
    if user.role != "admin":
        raise ApiError(403, "FORBIDDEN", "Se requiere acceso administrativo.")
    return user


def require_master(user: User = Depends(require_admin)) -> User:
    if not user.is_master:
        raise ApiError(403, "MASTER_REQUIRED", "Solo la cuenta maestra administra accesos.")
    return user


def require_business(user: User = Depends(request_user)) -> User:
    if user.role != "business" or not user.business_id:
        raise ApiError(403, "FORBIDDEN", "Se requiere la cuenta del local.")
    return user


def require_student(user: User = Depends(request_user)) -> User:
    if user.role != "user":
        raise ApiError(403, "FORBIDDEN", "Se requiere una cuenta de estudiante.")
    return user


def revoke_user_sessions(db: Session, user: User) -> None:
    user.auth_version = (user.auth_version or 1) + 1
    db.execute(update(RefreshSession).where(RefreshSession.user_id == user.id,
                                          RefreshSession.revoked_at.is_(None)).values(revoked_at=utcnow()))


def require_origin(request: Request) -> None:
    if request.headers.get("origin") != request.app.state.settings.public_origin.rstrip("/"):
        raise ApiError(403, "ORIGIN_NOT_ALLOWED", "El origen de la solicitud no está permitido.")
