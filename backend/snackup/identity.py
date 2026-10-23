"""Contract authentication and explicit institutional student registration extension."""
import csv
import io
import re
import secrets
from datetime import timedelta
from urllib.parse import quote

import jwt
from fastapi import APIRouter, Body, Depends, Request, Response
from fastapi.responses import HTMLResponse, JSONResponse
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .auth import (JWT_AUDIENCE, JWT_ISSUER, PASSWORDS, REFRESH_COOKIE, as_utc,
                   current_user, ensure_account, hash_password, password_matches,
                   require_origin, revoke_user_sessions, token_hash)
from .common import iso, validate_body
from .db import get_db, new_id, utcnow
from .errors import ApiError
from .identity_models import (AcademicGroup, AcademicRecord, AccessRequest, Career,
                              RefreshSession, User, VerificationToken)
from .mailer import mail_available, send_mail

router = APIRouter()
EMAIL_PATTERN = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")


def normalize_email(value: str) -> str:
    if not isinstance(value, str):
        raise ApiError(422, "INVALID_EMAIL", "Escribe un correo válido.")
    normalized = value.strip().lower()
    if len(normalized) > 160 or not EMAIL_PATTERN.fullmatch(normalized):
        raise ApiError(422, "INVALID_EMAIL", "Escribe un correo válido.")
    return normalized


def serialize_user(user: User) -> dict:
    return {"id": user.id, "displayName": user.display_name, "email": user.email,
            "role": user.role, "businessId": user.business_id, "isActive": user.is_active,
            "isMaster": user.is_master, "version": user.version,
            "approvalStatus": user.approval_status, "emailVerified": user.email_verified}


def serialize_access_request(record: AccessRequest) -> dict:
    return {"id": record.id, "displayName": record.display_name, "email": record.email,
            "requestedRole": record.requested_role, "requestContext": record.request_context,
            "provider": record.provider, "emailVerified": record.email_verified,
            "approvalStatus": record.approval_status, "version": record.version,
            "createdAt": iso(record.created_at)}


def serialize_profile(user: User, db: Session) -> dict:
    result = {"id": user.id, "displayName": user.display_name, "role": user.role,
              "businessId": user.business_id, "isMaster": user.is_master,
              "email": user.email, "emailVerified": user.email_verified}
    academic = db.scalar(select(AcademicRecord).where(AcademicRecord.email == user.email,
                                                    AcademicRecord.is_active.is_(True)))
    if academic is not None:
        career = db.get(Career, academic.career_id) if academic.career_id else None
        group = db.get(AcademicGroup, academic.group_id) if academic.group_id else None
        result["academic"] = {"institutionalId": academic.institutional_id, "kind": academic.kind,
                              "careerId": academic.career_id, "careerName": career.name if career else None,
                              "groupId": academic.group_id, "groupName": group.name if group else None,
                              "verified": True}
    return result


def _cookie(response: Response, token: str, settings, expires_at) -> None:
    response.set_cookie(REFRESH_COOKIE, token, max_age=max(1, int((as_utc(expires_at) - utcnow()).total_seconds())),
                        httponly=True, secure=settings.public_origin.startswith("https://"),
                        samesite="strict", path="/api/v1/auth")
    response.headers["Cache-Control"] = "no-store"


def _clear_cookie(response: Response, settings) -> None:
    response.delete_cookie(REFRESH_COOKIE, path="/api/v1/auth", httponly=True,
                           secure=settings.public_origin.startswith("https://"), samesite="strict")
    response.headers["Cache-Control"] = "no-store"


def _issue_session(db: Session, user: User, response: Response, settings,
                   family_id: str | None = None, expires_at=None) -> dict:
    now = utcnow()
    raw = secrets.token_urlsafe(48)
    session = RefreshSession(id=new_id(), user_id=user.id, family_id=family_id or new_id(),
                             token_hash=token_hash(raw), auth_version=user.auth_version,
                             expires_at=expires_at or now + timedelta(days=settings.refresh_days))
    db.add(session)
    db.flush()
    expiry = min(now + timedelta(minutes=settings.access_token_minutes), as_utc(session.expires_at))
    access = jwt.encode({"sub": user.id, "sid": session.id, "ver": user.auth_version,
                         "iat": now, "exp": expiry, "iss": JWT_ISSUER, "aud": JWT_AUDIENCE},
                        settings.secret_key, algorithm="HS256")
    _cookie(response, raw, settings, session.expires_at)
    return {"tokens": {"accessToken": access, "accessTokenExpiresAt": iso(expiry)}}


def _mail_token(db: Session, user: User, settings, purpose: str, mailer=None) -> None:
    if not mail_available(settings):
        raise ApiError(503, "EMAIL_UNAVAILABLE", "El envío de correo aún no está configurado.")
    raw = secrets.token_urlsafe(32)
    now = utcnow()
    # Issuing a new email also invalidates all previous tokens for this purpose.
    db.execute(update(VerificationToken).where(VerificationToken.user_id == user.id,
                                               VerificationToken.purpose == purpose,
                                               VerificationToken.used_at.is_(None)).values(used_at=now))
    db.add(VerificationToken(user_id=user.id, email=user.email, purpose=purpose,
                             token_hash=token_hash(raw), expires_at=now + timedelta(minutes=30)))
    db.flush()
    if purpose == "verify":
        link = settings.public_origin.rstrip("/") + "/api/v1/auth/verify-email#token=" + quote(raw)
        subject = "Confirma tu correo de SnackUP"
        content = ("Confirma que este correo te pertenece. Abre el enlace y pulsa Confirmar correo.\n\n"
                   + link + "\n\nEl enlace vence en 30 minutos y se usa una sola vez. "
                   "Verificar el correo no otorga permisos administrativos. Si no solicitaste el registro, ignora este mensaje.")
    else:
        link = settings.public_origin.rstrip("/") + "/#/reset-password?token=" + quote(raw)
        subject = "Restablece tu contraseña de SnackUP"
        content = ("Solicitaste restablecer la contraseña de SnackUP:\n\n" + link +
                   "\n\nEl enlace vence en 30 minutos y se usa una sola vez. "
                   "Si no hiciste esta solicitud, ignora el mensaje.")
    (mailer or send_mail)(settings, user.email, subject, content)


def queue_verification(db: Session, user: User, settings, mailer=None) -> None:
    """Create a one-use token and deliver it. Caller owns commit/rollback."""
    _mail_token(db, user, settings, "verify", mailer)


@router.get("/auth/options")
def access_options(request: Request):
    return {"passwordLogin": True, "selfRegistration": mail_available(request.app.state.settings),
            "googleEnabled": False}


@router.post("/auth/login")
def login(request: Request, response: Response, data: dict = Body(...), db: Session = Depends(get_db, scope="function")):
    require_origin(request)
    validate_body("login", data)
    email = normalize_email(data["email"])
    user = db.scalar(select(User).where(User.email == email).with_for_update())
    if not password_matches(data["password"], user.password_hash if user else None):
        raise ApiError(401, "INVALID_CREDENTIALS", "Correo o contraseña incorrectos.")
    ensure_account(user, db)
    if PASSWORDS.check_needs_rehash(user.password_hash):
        user.password_hash = hash_password(data["password"])
    return _issue_session(db, user, response, request.app.state.settings)


@router.post("/auth/refresh")
def refresh(request: Request, response: Response, data: dict = Body(...), db: Session = Depends(get_db, scope="function")):
    require_origin(request)
    validate_body("refresh", data)
    raw = request.cookies.get(REFRESH_COOKIE, "")
    initial = db.scalar(select(RefreshSession).where(RefreshSession.token_hash == token_hash(raw))) if raw else None
    if initial is None:
        raise ApiError(401, "UNAUTHENTICATED", "La sesión no es válida.")
    # Account first, then token: the same lock order as administrative revocation.
    user = db.scalar(select(User).where(User.id == initial.user_id).with_for_update())
    session = db.scalar(select(RefreshSession).where(RefreshSession.id == initial.id).with_for_update()
                        .execution_options(populate_existing=True))
    if session.rotated_at is not None:
        db.execute(update(RefreshSession).where(RefreshSession.family_id == session.family_id)
                   .values(revoked_at=utcnow()))
        # Returning an error response (rather than raising) lets get_db commit
        # the revocation. An exception would roll this security action back.
        failure = JSONResponse({"error": {"code": "SESSION_REPLAY", "message": "La sesión fue revocada. Inicia sesión nuevamente."}}, status_code=401)
        _clear_cookie(failure, request.app.state.settings)
        return failure
    if (user is None or session.revoked_at is not None or as_utc(session.expires_at) <= utcnow()
            or session.auth_version != user.auth_version):
        raise ApiError(401, "UNAUTHENTICATED", "La sesión fue revocada.")
    ensure_account(user, db)
    session.rotated_at = utcnow()
    return _issue_session(db, user, response, request.app.state.settings, session.family_id, session.expires_at)


@router.post("/auth/logout", status_code=204)
def logout(request: Request, data: dict = Body(...), db: Session = Depends(get_db, scope="function")):
    require_origin(request)
    validate_body("logout", data)
    families = set()
    raw = request.cookies.get(REFRESH_COOKIE)
    if raw:
        session = db.scalar(select(RefreshSession).where(RefreshSession.token_hash == token_hash(raw)))
        if session:
            families.add(session.family_id)
    authorization = request.headers.get("authorization", "")
    scheme, _, access = authorization.partition(" ")
    if scheme.lower() == "bearer" and access:
        try:
            claims = jwt.decode(access, request.app.state.settings.secret_key, algorithms=["HS256"],
                                issuer=JWT_ISSUER, audience=JWT_AUDIENCE,
                                options={"verify_exp": False, "require": ["sid", "sub", "iss", "aud"]})
            session = db.get(RefreshSession, claims["sid"])
            if session and session.user_id == claims["sub"]:
                families.add(session.family_id)
        except (jwt.InvalidTokenError, TypeError):
            pass
    if families:
        # Serialize against refresh so a concurrent rotation cannot survive logout.
        users = list(db.scalars(select(RefreshSession.user_id).where(RefreshSession.family_id.in_(families)).distinct()))
        list(db.scalars(select(User).where(User.id.in_(users)).order_by(User.id).with_for_update()))
        db.execute(update(RefreshSession).where(RefreshSession.family_id.in_(families)).values(revoked_at=utcnow()))
    response = Response(status_code=204)
    _clear_cookie(response, request.app.state.settings)
    return response


@router.get("/users/me")
def profile(user: User = Depends(current_user), db: Session = Depends(get_db, scope="function")):
    return serialize_profile(user, db)


@router.post("/auth/register", status_code=202)
def register(request: Request, data: dict = Body(...), db: Session = Depends(get_db, scope="function")):
    validate_body("requestAccess", data)
    settings = request.app.state.settings
    if not mail_available(settings):
        raise ApiError(503, "EMAIL_UNAVAILABLE", "El registro requiere envío de correo configurado.")
    email = normalize_email(data["email"])
    if not data["displayName"].strip():
        raise ApiError(422, "INVALID_NAME", "Escribe tu nombre.")
    if db.scalar(select(User.id).where(User.email == email)):
        return {"status": "received"}
    user = User(id=new_id(), email=email, display_name=data["displayName"].strip(),
                password_hash=hash_password(data["password"]), role="pending", is_active=False,
                is_master=False, approval_status="pending", email_verified=False)
    try:
        with db.begin_nested():
            db.add(user)
            db.flush()
            db.add(AccessRequest(user_id=user.id, email=email, display_name=user.display_name,
                                 requested_role=data["requestedRole"], request_context=data["context"].strip()))
            queue_verification(db, user, settings, getattr(request.app.state, "mailer", None))
    except IntegrityError:
        # Concurrent duplicate: do not replace its password/role or expose existence.
        if not db.scalar(select(User.id).where(User.email == email)):
            raise
    return {"status": "received"}


@router.post("/student/register", status_code=202)
def register_student(request: Request, data: dict = Body(...), db: Session = Depends(get_db, scope="function")):
    if set(data) != {"email", "password"} or not isinstance(data.get("password"), str):
        raise ApiError(422, "INVALID_INPUT", "Se requieren únicamente correo y contraseña.")
    email = normalize_email(data["email"])
    encoded = hash_password(data["password"])
    settings = request.app.state.settings
    if not mail_available(settings):
        raise ApiError(503, "EMAIL_UNAVAILABLE", "El registro requiere envío de correo configurado.")
    domains = {x.strip().lower() for x in settings.student_email_domains.split(",") if x.strip()}
    if not domains:
        raise ApiError(503, "INSTITUTION_NOT_CONFIGURED", "Falta configurar los dominios institucionales.")
    record = db.scalar(select(AcademicRecord).where(AcademicRecord.email == email))
    eligible = (email.rsplit("@", 1)[1] in domains and record is not None
                and record.kind == "student" and record.is_active)
    # The same acknowledgement prevents enumeration of the academic roster.
    if not eligible or db.scalar(select(User.id).where(User.email == email)):
        return {"status": "received"}
    user = User(id=new_id(), email=email, display_name=record.display_name, password_hash=encoded,
                role="user", is_master=False, is_active=True, approval_status="approved", email_verified=False)
    try:
        with db.begin_nested():
            db.add(user)
            db.flush()
            queue_verification(db, user, settings, getattr(request.app.state, "mailer", None))
    except IntegrityError:
        if not db.scalar(select(User.id).where(User.email == email)):
            raise
    return {"status": "received"}


@router.post("/auth/forgot-password", status_code=204)
def forgot_password(request: Request, data: dict = Body(...), db: Session = Depends(get_db, scope="function")):
    validate_body("forgotPassword", data)
    if not mail_available(request.app.state.settings):
        raise ApiError(503, "EMAIL_UNAVAILABLE", "La recuperación requiere envío de correo configurado.")
    email = normalize_email(data["email"])
    user = db.scalar(select(User).where(User.email == email).with_for_update())
    if user is not None and user.approval_status != "rejected":
        _mail_token(db, user, request.app.state.settings, "reset", getattr(request.app.state, "mailer", None))
    return Response(status_code=204)


@router.post("/auth/resend-verification", status_code=202)
def resend_verification(request: Request, data: dict = Body(...), db: Session = Depends(get_db, scope="function")):
    if set(data) != {"email"}:
        raise ApiError(422, "INVALID_INPUT", "Se requiere únicamente el correo.")
    email = normalize_email(data["email"])
    settings = request.app.state.settings
    if not mail_available(settings):
        raise ApiError(503, "EMAIL_UNAVAILABLE", "El envío de correo aún no está configurado.")
    user = db.scalar(select(User).where(User.email == email).with_for_update())
    if user is not None and not user.email_verified and user.approval_status != "rejected":
        queue_verification(db, user, settings, getattr(request.app.state, "mailer", None))
    return {"status": "received"}


def _consume_token(db: Session, raw: str, purpose: str) -> tuple[VerificationToken, User]:
    code = "RESET_TOKEN_INVALID" if purpose == "reset" else "VERIFICATION_TOKEN_INVALID"
    if not isinstance(raw, str) or not 20 <= len(raw) <= 256:
        raise ApiError(422, code, "El enlace expiró o ya fue utilizado.")
    initial = db.scalar(select(VerificationToken).where(VerificationToken.token_hash == token_hash(raw)))
    if initial is None:
        raise ApiError(422, code, "El enlace expiró o ya fue utilizado.")
    user = db.scalar(select(User).where(User.id == initial.user_id).with_for_update())
    record = db.scalar(select(VerificationToken).where(VerificationToken.id == initial.id).with_for_update()
                       .execution_options(populate_existing=True))
    if (record.purpose != purpose or record.used_at is not None or as_utc(record.expires_at) <= utcnow()
            or user is None or user.email != record.email):
        raise ApiError(422, code, "El enlace expiró o ya fue utilizado.")
    record.used_at = utcnow()
    return record, user


@router.post("/auth/reset-password", status_code=204)
def reset_password(request: Request, data: dict = Body(...), db: Session = Depends(get_db, scope="function")):
    require_origin(request)
    validate_body("resetPassword", data)
    _, user = _consume_token(db, data["token"], "reset")
    user.password_hash = hash_password(data["newPassword"])
    user.version += 1
    revoke_user_sessions(db, user)
    response = Response(status_code=204)
    _clear_cookie(response, request.app.state.settings)
    return response


@router.post("/auth/verify-email", status_code=204)
def verify_email(request: Request, data: dict = Body(...), db: Session = Depends(get_db, scope="function")):
    require_origin(request)
    if set(data) != {"token"}:
        raise ApiError(422, "INVALID_INPUT", "Se requiere un token de verificación.")
    _, user = _consume_token(db, data["token"], "verify")
    user.email_verified = True
    user.version += 1
    # The shared identity lock order is User -> token/request/roster children.
    access_request = db.scalar(select(AccessRequest).where(AccessRequest.user_id == user.id).with_for_update()
                               .execution_options(populate_existing=True))
    if access_request is not None:
        access_request.email_verified = True
        access_request.version += 1
    return Response(status_code=204)


@router.get("/auth/google/start")
def google_disabled():
    raise ApiError(503, "GOOGLE_DISABLED", "El inicio institucional con Google todavía no está configurado.")


@router.get("/auth/verify-email", response_class=HTMLResponse, include_in_schema=False)
def verification_page():
    nonce = secrets.token_urlsafe(24)
    document = """<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Confirmar correo · SnackUP</title><body><main><h1>Confirma tu correo de SnackUP</h1>
<p>Al confirmar, acreditas que este correo te pertenece. Los accesos administrativos requieren autorización adicional.</p>
<button id="confirm" type="button">Confirmar correo</button><p id="message" role="status"></p><a href="/">Volver a SnackUP</a></main>
<script nonce="__NONCE__">const token=new URLSearchParams(location.hash.slice(1)).get('token');history.replaceState(null,'',location.pathname);
const button=document.getElementById('confirm'),message=document.getElementById('message');
if(!token){button.disabled=true;message.textContent='Abre el enlace que recibiste por correo.';}
button.addEventListener('click',async()=>{button.disabled=true;message.textContent='Confirmando…';try{
const response=await fetch(location.pathname,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token})});
if(response.ok){message.textContent='Correo confirmado. Ya puedes volver a SnackUP. Si solicitaste acceso al personal, espera la autorización.';}
else{const data=await response.json();message.textContent=data.error?.message||'No se pudo confirmar el correo.';button.disabled=false;}
}catch{message.textContent='No se pudo contactar al servidor. Intenta nuevamente.';button.disabled=false;}});</script></body></html>""".replace("__NONCE__", nonce)
    return HTMLResponse(document, headers={"Cache-Control": "no-store", "Referrer-Policy": "no-referrer",
                        "Content-Security-Policy": f"default-src 'none'; script-src 'nonce-{nonce}'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'"})


ROSTER_COLUMNS = {"email", "institutional_id", "display_name", "kind", "career_id", "career_name",
                  "group_id", "group_name", "is_active"}


def _lock_roster_users(db: Session, emails: set[str]) -> dict[str, User]:
    # Account administration first locks active admins in ID order, then its
    # target. Imports follow that same order before touching roster rows.
    # Otherwise an import of an admin+student could deadlock against a master
    # assigning that student while holding the administrative account locks.
    list(db.scalars(select(User).where(User.role == "admin", User.is_active.is_(True))
                    .order_by(User.id).with_for_update().execution_options(populate_existing=True)))
    selected_ids = set()
    ordered_emails = sorted(emails)
    for start in range(0, len(ordered_emails), 1000):
        selected_ids.update(db.scalars(select(User.id).where(User.email.in_(ordered_emails[start:start + 1000]))))
    # Bounded parameter batches retain one global ID lock order, including for
    # large imports. Newly created accounts still fail the live roster check.
    ordered_ids = sorted(selected_ids)
    users = {}
    for start in range(0, len(ordered_ids), 1000):
        for user in db.scalars(select(User).where(User.id.in_(ordered_ids[start:start + 1000]))
                               .order_by(User.id).with_for_update().execution_options(populate_existing=True)):
            users[user.email] = user
    return users


def import_roster_csv(db: Session, content: str, source: str) -> dict:
    """Atomic, explicit upsert of an authorized CSV; absent records stay unchanged.

    Caller commits. IDs are institution-owned opaque values. Only this trusted
    import supplies careers/groups; email naming patterns are never interpreted.
    Set is_active=false explicitly to revoke a student omitted from a later list.
    """
    if not isinstance(source, str) or not 1 <= len(source.strip()) <= 200:
        raise ValueError("source must identify the authorized roster (1–200 characters)")
    if len(content.encode("utf-8")) > 10 * 1024 * 1024:
        raise ValueError("Roster must not exceed 10 MiB")
    reader = csv.DictReader(io.StringIO(content.lstrip("\ufeff")))
    if not reader.fieldnames or set(reader.fieldnames) != ROSTER_COLUMNS or len(reader.fieldnames) != len(ROSTER_COLUMNS):
        raise ValueError("CSV columns must be: " + ",".join(sorted(ROSTER_COLUMNS)))
    rows, emails, identities, careers, groups = [], set(), set(), {}, {}
    for line, original in enumerate(reader, 2):
        if line > 100002 or None in original or any(value is None for value in original.values()):
            raise ValueError(f"Invalid CSV row {line}")
        row = {key: value.strip() for key, value in original.items()}
        try:
            row["email"] = normalize_email(row["email"])
        except ApiError as exc:
            raise ValueError(f"Invalid email on row {line}") from exc
        if (row["email"] in emails or not 1 <= len(row["institutional_id"]) <= 100
                or not 1 <= len(row["display_name"]) <= 100 or row["kind"] not in ("student", "staff")
                or row["is_active"].lower() not in ("true", "false", "1", "0")):
            raise ValueError(f"Invalid or duplicate identity on row {line}")
        identity = (row["kind"], row["institutional_id"])
        if identity in identities:
            raise ValueError(f"Duplicate institutional identity on row {line}")
        if (len(row["career_id"]) > 128 or len(row["group_id"]) > 128 or len(row["career_name"]) > 160
                or len(row["group_name"]) > 160 or bool(row["career_id"]) != bool(row["career_name"])
                or bool(row["group_id"]) != bool(row["group_name"])
                or (row["kind"] == "student" and not row["career_id"])
                or (row["group_id"] and not row["career_id"])):
            raise ValueError(f"Invalid career/group on row {line}")
        if row["career_id"]:
            existing = careers.setdefault(row["career_id"], row["career_name"])
            if existing != row["career_name"]:
                raise ValueError(f"Conflicting career names on row {line}")
        if row["group_id"]:
            existing = groups.setdefault(row["group_id"], (row["career_id"], row["group_name"]))
            if existing != (row["career_id"], row["group_name"]):
                raise ValueError(f"Conflicting group definitions on row {line}")
        row["is_active"] = row["is_active"].lower() in ("true", "1")
        emails.add(row["email"])
        identities.add(identity)
        rows.append(row)
    if not rows:
        raise ValueError("Roster must contain at least one record")
    created, updated = 0, 0
    try:
        with db.begin_nested():
            users = _lock_roster_users(db, emails)
            for key, name in sorted(careers.items()):
                career = db.get(Career, key)
                if career is None:
                    db.add(Career(id=key, name=name, is_active=True))
                else:
                    career.name = name
            db.flush()
            for key, (career_id, name) in sorted(groups.items()):
                group = db.get(AcademicGroup, key)
                if group is None:
                    db.add(AcademicGroup(id=key, career_id=career_id, name=name, is_active=True))
                elif group.career_id != career_id:
                    raise ValueError(f"Group {key} already belongs to a different career")
                else:
                    group.name = name
            db.flush()
            for row in sorted(rows, key=lambda item: item["email"]):
                record = db.scalar(select(AcademicRecord).where(AcademicRecord.email == row["email"]).with_for_update()
                                   .execution_options(populate_existing=True))
                existing_identity = db.scalar(select(AcademicRecord).where(AcademicRecord.kind == row["kind"],
                                                    AcademicRecord.institutional_id == row["institutional_id"]))
                if existing_identity is not None and existing_identity.email != row["email"]:
                    raise ValueError("Institutional identity already has a different email; resolve explicitly before importing")
                if record is not None and (record.kind != row["kind"] or record.institutional_id != row["institutional_id"]):
                    raise ValueError("Email already belongs to a different institutional identity")
                if record is None:
                    record = AcademicRecord(email=row["email"])
                    db.add(record)
                    created += 1
                else:
                    updated += 1
                for key in ("institutional_id", "display_name", "kind", "is_active"):
                    setattr(record, key, row[key])
                record.career_id = row["career_id"] or None
                record.group_id = row["group_id"] or None
                record.source = source.strip()
                record.updated_at = utcnow()
                if not record.is_active:
                    user = users.get(record.email)
                    if user is not None:
                        revoke_user_sessions(db, user)
                db.flush()
    except IntegrityError as exc:
        raise ValueError("Roster conflicts with existing institutional identities; no rows imported") from exc
    return {"created": created, "updated": updated, "careers": len(careers), "groups": len(groups)}
