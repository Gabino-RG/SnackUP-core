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


def ensure_account(user: User, db: Session) -> None:
    if user.approval_status == "pending":
        raise ApiError(403, "ACCESS_PENDING", "La solicitud está pendiente de autorización.")
    if user.approval_status == "rejected":
        raise ApiError(403, "ACCESS_REJECTED", "La solicitud no fue autorizada.")
    if not user.is_active or user.role not in ("admin", "business", "user"):
        raise ApiError(403, "ACCESS_REVOKED", "El acceso está suspendido.")
    if not user.email_verified:
        raise ApiError(403, "EMAIL_NOT_VERIFIED", "Confirma tu correo antes de iniciar sesión.")
    if user.role == "business":
        # Avoid a circular model import. Businesses are registered at app creation.
        business_table = User.metadata.tables.get("businesses")
        business = None if not user.business_id or business_table is None else db.execute(
            select(business_table.c.id).where(business_table.c.id == user.business_id,
                                             business_table.c.is_active.is_(True))
        ).first()
        if business is None:
            raise ApiError(403, "ACCESS_REVOKED", "El local asignado no está activo.")
    record = db.scalar(select(AcademicRecord).where(AcademicRecord.email == user.email)
                       .execution_options(populate_existing=True))
    # A missing staff roster does not remove an explicitly granted SnackUP role.
    # Once an authoritative record exists, its inactivity blocks every role.
    # Refresh an already-loaded record too: writes recheck after locking User.
    if record is not None and not record.is_active:
        raise ApiError(403, "ACCESS_REVOKED", "El padrón institucional no autoriza el acceso.")
    if user.role == "user" and (record is None or record.kind != "student"):
        raise ApiError(403, "ACCESS_REVOKED", "El padrón institucional no autoriza el acceso.")


def verify_access_token(token: str, db: Session, settings) -> User:
    try:
        claims = jwt.decode(token, settings.secret_key, algorithms=["HS256"],
                            issuer=JWT_ISSUER, audience=JWT_AUDIENCE,
                            options={"require": ["exp", "iat", "sub", "sid", "ver", "iss", "aud"]})
    except jwt.ExpiredSignatureError:
        raise ApiError(401, "TOKEN_EXPIRED", "La sesión requiere renovación.") from None
    except jwt.InvalidTokenError:
        raise ApiError(401, "UNAUTHENTICATED", "La sesión no es válida.") from None
    sid = claims.get("sid")
    if not isinstance(sid, str) or not isinstance(claims.get("sub"), str):
        raise ApiError(401, "UNAUTHENTICATED", "La sesión no es válida.")
    # Revalidation after waiting on a write lock must observe a logout or an
    # administrative revocation committed while this Session was waiting.
    session = db.get(RefreshSession, sid, populate_existing=True)
    user = db.get(User, claims["sub"], populate_existing=True)
    if (session is None or user is None or session.user_id != user.id or
            session.revoked_at is not None or as_utc(session.expires_at) <= utcnow() or
            claims.get("ver") != user.auth_version or session.auth_version != user.auth_version):
        raise ApiError(401, "UNAUTHENTICATED", "La sesión fue revocada.")
    ensure_account(user, db)
    return user


def current_user(request: Request, db: Session = Depends(get_db, scope="function"),
                 credentials: HTTPAuthorizationCredentials | None = Security(BEARER)) -> User:
    authorization = request.headers.get("authorization", "")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise ApiError(401, "UNAUTHENTICATED", "Inicia sesión para continuar.")
    return verify_access_token(token, db, request.app.state.settings)


def require_admin(user: User = Depends(current_user)) -> User:
    if user.role != "admin":
        raise ApiError(403, "FORBIDDEN", "Se requiere acceso administrativo.")
    return user


def require_master(user: User = Depends(require_admin)) -> User:
    if not user.is_master:
        raise ApiError(403, "MASTER_REQUIRED", "Solo la cuenta maestra administra accesos.")
    return user


def require_business(user: User = Depends(current_user)) -> User:
    if user.role != "business" or not user.business_id:
        raise ApiError(403, "FORBIDDEN", "Se requiere la cuenta del local.")
    return user


def require_student(user: User = Depends(current_user)) -> User:
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
