"""Canonical identity behavior, including the audited registration collision."""
from concurrent.futures import ThreadPoolExecutor
import re
from threading import Event

import jwt
import pytest
from sqlalchemy import event, select, update

from snackup.auth import JWT_AUDIENCE, JWT_ISSUER, REFRESH_COOKIE, password_matches
from snackup.db import utcnow
from snackup.identity_models import (AcademicRecord, AccessRequest, AccountAuditEvent,
                                     RefreshSession, User, VerificationToken)

pytestmark = pytest.mark.v3
PASSWORD = "Test-Only-Password-392!"
ORIGIN = {"Origin": "http://testserver"}


def new_student(app, email="new@students.example.edu", control="CTRL-V3"):
    with app.state.db.sessions.begin() as db:
        db.add(AcademicRecord(email=email, institutional_id=control, display_name="Nombre del padrón",
                             kind="student", career_id="career-1", group_id="group-1", source="isolated V3 fixture"))
    return {"email": email, "password": PASSWORD, "displayName": "Nombre escrito", "numeroDeControl": control}


def mail_token(app):
    return re.search(r"token=([A-Za-z0-9_-]+)", app.state.mailbox[-1]["body"]).group(1)


def mobile_login(client, identity="student"):
    domain = "students.example.edu" if "student" in identity else "staff.example.edu"
    response = client.post("/api/v1/auth/login", json={"email": f"{identity}@{domain}", "password": PASSWORD})
    assert response.status_code == 200
    return response.json()


def test_v3_registration_requires_roster_and_email_before_any_session(app, client):
    body = new_student(app)
    response = client.post("/api/v1/auth/register", json=body, headers=ORIGIN)
    assert response.status_code == 202 and response.json() == {"status": "received"}
    assert "tokens" not in response.json() and REFRESH_COOKIE not in response.cookies
    pending = client.post("/api/v1/auth/login", json={"email": body["email"], "password": PASSWORD})
    assert pending.status_code == 403 and pending.json()["error"]["code"] == "EMAIL_NOT_VERIFIED"
    raw = mail_token(app)
    app.state.settings.password_reset_frontend_path = "/paneles/"
    app.state.settings.student_password_reset_frontend_path = "/"
    confirmation = client.post("/api/v1/auth/verify-email", json={"token": raw}, headers=ORIGIN)
    assert confirmation.status_code == 204
    assert confirmation.headers["X-SnackUP-Login-Path"] == "/"
    result = client.post("/api/v1/auth/login", json={"email": body["email"], "password": PASSWORD}).json()
    assert result["user"]["role"] == "ALUMNO"
    assert result["user"]["displayName"] == "Nombre del padrón"
    assert result["user"]["numeroDeControl"] == body["numeroDeControl"]
    assert result["user"]["institutionalVerifiedAt"] and result["user"]["lastLoginAt"]
    claims = jwt.decode(result["tokens"]["accessToken"], app.state.settings.secret_key,
                        algorithms=["HS256"], issuer=JWT_ISSUER, audience=JWT_AUDIENCE)
    assert claims["role"] == "ALUMNO" and "bid" not in claims
    assert client.post("/api/v1/auth/verify-email", json={"token": raw}, headers=ORIGIN).status_code == 422


def test_v3_registration_rejects_role_and_mismatched_control_without_account(app, client):
    body = new_student(app)
    assert client.post("/api/v1/auth/register", json={**body, "role": "ADMIN"}).status_code == 422
    assert client.post("/api/v1/auth/register", json={**body, "numeroDeControl": "WRONG"}).status_code == 202
    assert not app.state.mailbox
    with app.state.db.sessions() as db:
        assert db.scalar(select(User).where(User.email == body["email"])) is None


@pytest.mark.parametrize("verify_prefix", ["/api/v1", "/api/legacy/v1"])
def test_pending_staff_collision_recovers_only_after_email_proof(app, client, password_hash, verify_prefix):
    body = new_student(app)
    body["password"] = "Owner recovered password 123!"
    with app.state.db.sessions.begin() as db:
        user = User(id="collision", email=body["email"], display_name="Unverified request",
                    role="pending", is_active=False, approval_status="pending", email_verified=False,
                    password_hash=password_hash)
        db.add(user)
        db.flush()
        db.add(AccessRequest(user_id=user.id, email=user.email, display_name=user.display_name,
                             requested_role="business", request_context="Old request"))
    assert client.post("/api/v1/auth/register", json=body, headers=ORIGIN).status_code == 202
    with app.state.db.sessions() as db:
        user = db.get(User, "collision")
        assert user.role == "pending" and user.password_hash == password_hash and not user.email_verified
        token = db.scalar(select(VerificationToken).where(VerificationToken.user_id == user.id))
        assert body["password"] not in str(token.registration_data)
    assert client.post(verify_prefix + "/auth/verify-email", json={"token": mail_token(app)}, headers=ORIGIN).status_code == 204
    with app.state.db.sessions() as db:
        user = db.get(User, "collision")
        assert user.role == "user" and user.is_active and user.email_verified and not user.is_master
        assert password_matches(body["password"], user.password_hash)
        assert db.scalar(select(AccessRequest).where(AccessRequest.user_id == user.id)).approval_status == "rejected"
        assert db.scalar(select(AccountAuditEvent).where(AccountAuditEvent.target_id == user.id)) is not None
        assert db.scalar(select(VerificationToken).where(VerificationToken.user_id == user.id)).registration_data is None
    login = client.post("/api/v1/auth/login", json={"email": body["email"], "password": body["password"]})
    assert login.status_code == 200 and login.json()["user"]["role"] == "ALUMNO"
    assert client.post("/api/v1/auth/register", json={**body, "password": "Another fake password123!"}).status_code == 202
    assert client.post("/api/v1/auth/login", json={"email": body["email"], "password": body["password"]}).status_code == 200


@pytest.mark.parametrize(("resend_prefix", "verify_prefix"), [
    ("/api/v1", "/api/legacy/v1"),
    ("/api/legacy/v1", "/api/v1"),
])
def test_student_proof_survives_cross_api_resend_and_rechecks_current_roster(app, client, resend_prefix, verify_prefix):
    body = new_student(app)
    assert client.post("/api/v1/auth/register", json=body).status_code == 202
    original = mail_token(app)
    assert client.post(resend_prefix + "/auth/resend-verification", json={"email": body["email"]},
                       headers=ORIGIN).status_code == 202
    current = mail_token(app)
    verify = verify_prefix + "/auth/verify-email"
    assert client.post(verify, headers=ORIGIN, json={"token": original}).status_code == 422
    with app.state.db.sessions.begin() as db:
        assert db.scalar(select(VerificationToken).where(VerificationToken.used_at.is_not(None))).registration_data is None
        db.execute(update(AcademicRecord).where(AcademicRecord.email == body["email"]).values(is_active=False))
    denied = client.post(verify, headers=ORIGIN, json={"token": current})
    assert denied.status_code == 403 and denied.json()["error"]["code"] == "ACCESS_REVOKED"
    with app.state.db.sessions.begin() as db:
        assert not db.scalar(select(User.email_verified).where(User.email == body["email"]))
        db.execute(update(AcademicRecord).where(AcademicRecord.email == body["email"]).values(is_active=True))
    assert client.post(verify, headers=ORIGIN, json={"token": current}).status_code == 204
    assert client.post(verify, headers=ORIGIN, json={"token": current}).status_code == 422


def test_v3_browser_cookie_and_native_token_have_distinct_contracts(app, client):
    web = client.post("/api/v1/auth/login", json={"email": "student@students.example.edu", "password": PASSWORD}, headers=ORIGIN)
    assert web.status_code == 200
    assert "refreshToken" not in web.json()["tokens"]
    cookie = web.headers["set-cookie"]
    assert "HttpOnly" in cookie and "SameSite=strict" in cookie and "Path=/api" in cookie
    assert client.post("/api/v1/auth/refresh").status_code == 403
    native = mobile_login(client)
    assert native["tokens"]["refreshToken"]
    assert client.post("/api/v1/auth/refresh", json={"refreshToken": native["tokens"]["refreshToken"]}, headers=ORIGIN).status_code == 422
    renewed = client.post("/api/v1/auth/refresh", headers=ORIGIN)
    assert renewed.status_code == 200 and "refreshToken" not in renewed.json()["tokens"]
    assert client.post("/api/v1/auth/logout").status_code == 403
    assert client.post("/api/v1/auth/logout", headers={"Origin": "https://untrusted.example"}).status_code == 403
    assert client.post("/api/v1/auth/logout", headers=ORIGIN).status_code == 204
    assert client.get("/api/v1/users/me", headers={"Authorization": "Bearer " + renewed.json()["tokens"]["accessToken"]}).status_code == 401


def test_v3_openapi_declares_bearer_without_changing_authentication_errors(app, client):
    schema = app.openapi()
    assert schema["components"]["securitySchemes"]["BearerAuth"] == {"type": "http", "scheme": "bearer", "bearerFormat": "JWT"}
    assert schema["paths"]["/api/v1/users/me"]["get"]["security"] == [{"BearerAuth": []}]
    assert "security" not in schema["paths"]["/api/v1/auth/login"]["post"]
    assert client.get("/api/v1/users/me").status_code == 401
    assert client.get("/api/v1/users/me", headers={"Authorization": "Basic invalid"}).status_code == 401


def test_v3_native_refresh_rotates_hash_and_replay_revokes_family(app, client):
    first = mobile_login(client)["tokens"]
    rotated = client.post("/api/v1/auth/refresh", json={"refreshToken": first["refreshToken"]})
    assert rotated.status_code == 200
    second = rotated.json()["tokens"]
    assert first["refreshToken"] != second["refreshToken"]
    with app.state.db.sessions() as db:
        sessions = list(db.scalars(select(RefreshSession).where(RefreshSession.user_id == "student")))
        previous = next(s for s in sessions if s.rotated_at is not None)
        assert previous.replaced_by_id
        assert all(s.token_hash not in {first["refreshToken"], second["refreshToken"]} for s in sessions)
    assert client.post("/api/v1/auth/refresh", json={"refreshToken": first["refreshToken"]}).status_code == 401
    assert client.get("/api/v1/users/me", headers={"Authorization": "Bearer " + second["accessToken"]}).status_code == 401


def test_v3_logout_revokes_only_the_selected_session(client):
    first = mobile_login(client)["tokens"]
    second = mobile_login(client)["tokens"]
    assert client.post("/api/v1/auth/logout", json={"refreshToken": first["refreshToken"]}).status_code == 204
    assert client.get("/api/v1/users/me", headers={"Authorization": "Bearer " + first["accessToken"]}).status_code == 401
    assert client.get("/api/v1/users/me", headers={"Authorization": "Bearer " + second["accessToken"]}).status_code == 200


def test_only_own_student_profile_exposes_current_roster_names(app, client, tokens):
    with app.state.db.sessions.begin() as db:
        other = db.scalar(select(AcademicRecord).where(AcademicRecord.institutional_id == "ID-other-student"))
        other.group_id = None
    path = "/api/v1/users/me"
    own = client.get(path, headers=tokens["student"]).json()
    assert own["academic"] == {"careerName": "Desarrollo de Software", "groupName": "DSM-1"}
    assert client.patch(path, headers=tokens["student"], json={
        "expectedVersion": own["version"], "avatarUrl": None
    }).json()["academic"] == own["academic"]
    other = client.get(path, headers=tokens["other-student"]).json()
    assert other["academic"] == {"careerName": "Desarrollo de Software", "groupName": None}
    for role in ("operator", "master"):
        assert "academic" not in client.get(path, headers=tokens[role]).json()
    listing = client.get("/api/v1/admin/users", headers=tokens["master"])
    assert listing.status_code == 200 and listing.json()["data"]
    assert all("academic" not in item for item in listing.json()["data"])


@pytest.mark.postgres
def test_v3_logout_winning_user_lock_prevents_a_waiting_profile_write(app, client):
    if app.state.db.engine.dialect.name != "postgresql":
        pytest.skip("Real PostgreSQL is required to verify revocation while waiting on a row lock")
    login = mobile_login(client)
    bearer = login["tokens"]["accessToken"]
    sid = jwt.decode(bearer, options={"verify_signature": False})["sid"]
    waiting = Event()

    def before_execute(connection, cursor, statement, parameters, context, many):
        if "FOR UPDATE" in statement and "users" in statement:
            waiting.set()

    # Reproduce the exact logout lock/mutation, withholding its commit so the
    # second request authenticates against the prior committed session first.
    blocker = app.state.db.sessions()
    blocker.scalar(select(User).where(User.id == "student").with_for_update())
    blocker.execute(update(RefreshSession).where(RefreshSession.id == sid).values(revoked_at=utcnow()))
    event.listen(app.state.db.engine, "before_cursor_execute", before_execute)
    try:
        with ThreadPoolExecutor(max_workers=1) as pool:
            pending = pool.submit(client.patch, "/api/v1/users/me",
                                  json={"avatarUrl": None, "expectedVersion": login["user"]["version"]},
                                  headers={"Authorization": "Bearer " + bearer})
            try:
                assert waiting.wait(5), "The profile write did not reach the User lock"
                blocker.commit()
                response = pending.result(timeout=10)
                assert response.status_code == 401
                assert response.json()["error"]["code"] == "UNAUTHENTICATED"
            finally:
                blocker.rollback()
    finally:
        event.remove(app.state.db.engine, "before_cursor_execute", before_execute)
        blocker.close()
    with app.state.db.sessions() as db:
        assert db.get(User, "student").version == login["user"]["version"]


def test_v3_native_reset_revokes_existing_session_and_never_echoes_password(app, client):
    tokens = mobile_login(client)["tokens"]
    assert client.post("/api/v1/auth/forgot-password", json={"email": "student@students.example.edu"}).status_code == 204
    raw = mail_token(app)
    password = "Owner changed password 987!"
    response = client.post("/api/v1/auth/reset-password", json={"token": raw, "newPassword": password})
    assert response.status_code == 204 and not response.content
    assert client.get("/api/v1/users/me", headers={"Authorization": "Bearer " + tokens["accessToken"]}).status_code == 401
    assert client.post("/api/v1/auth/login", json={"email": "student@students.example.edu", "password": password}).status_code == 200


def test_v3_kitchen_jwt_business_claim_and_email_unavailability_are_explicit(app, client):
    result = mobile_login(client, "operator")
    claims = jwt.decode(result["tokens"]["accessToken"], app.state.settings.secret_key,
                        algorithms=["HS256"], issuer=JWT_ISSUER, audience=JWT_AUDIENCE)
    assert result["user"]["role"] == claims["role"] == "COCINA" and claims["bid"] == "business-1"
    app.state.settings.smtp_host = ""
    assert client.get("/api/v1/auth/options").json()["selfRegistration"] is False
    assert client.post("/api/v1/auth/register", json=new_student(app)).status_code == 503
    assert client.get("/api/v1/auth/google/start").status_code == 503
