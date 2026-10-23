"""Security and institutional identity behavior against the real application."""
import os
import re
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from types import SimpleNamespace
from urllib.parse import quote
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event, func, select, text

from snackup.auth import REFRESH_COOKIE, ensure_account, hash_password, verify_access_token
from snackup.config import Settings
from snackup.db import Base, utcnow
from snackup.errors import ApiError
from snackup.identity import import_roster_csv
from snackup.identity_models import AcademicRecord, AccessRequest, Career, RefreshSession, User, VerificationToken
from snackup.main import create_app
from snackup.operation_models import Business

PASSWORD = "Valid password 2026!"
COLUMNS = "email,institutional_id,display_name,kind,career_id,career_name,group_id,group_name,is_active\n"
ROSTER = COLUMNS + "student@school.test,S-100,Student Example,student,ENG,Engineering,G1,First group,true\n"


@pytest.fixture
def identity_env(tmp_path):
    database_url = os.environ.get("SNACKUP_TEST_DATABASE_URL")
    schema = None
    if database_url:
        schema = "test_identity_" + uuid4().hex
        management = create_engine(database_url)
        with management.begin() as connection:
            connection.execute(text(f'CREATE SCHEMA "{schema}"'))
        database_url += ("&" if "?" in database_url else "?") + "options=" + quote("-c search_path=" + schema)
    else:
        database_url = "sqlite:///" + (tmp_path / "identity.db").as_posix()
    settings = Settings(environment="test", database_url=database_url, secret_key="test-only-" + "s" * 48,
                        public_origin="https://testserver", admin_email_domains="school.test",
                        student_email_domains="school.test", smtp_host="unused.test", smtp_from="no-reply@school.test",
                        media_dir=tmp_path / "media", background_events=False)
    app = create_app(settings)
    Base.metadata.create_all(app.state.db.engine)
    emails = []
    app.state.mailer = lambda settings, recipient, subject, body: emails.append({"to": recipient, "subject": subject, "body": body})
    with app.state.db.sessions.begin() as db:
        db.add(Business(id="local", name="Test kitchen", cafeteria_id="cafeteria", cafeteria_name="Cafeteria", is_active=True))
        db.flush()
        db.add(User(id="master", email="master@school.test", display_name="Master", password_hash=hash_password(PASSWORD),
                    role="admin", is_master=True, is_active=True, approval_status="approved", email_verified=True))
        db.add(User(id="operator", email="operator@school.test", display_name="Operator", password_hash=hash_password(PASSWORD),
                    role="business", business_id="local", is_master=False, is_active=True,
                    approval_status="approved", email_verified=True))
        import_roster_csv(db, ROSTER, "authorized-test-roster")
    with TestClient(app, base_url=settings.public_origin, headers={"Origin": settings.public_origin}) as client:
        yield SimpleNamespace(client=client, app=app, db=app.state.db.sessions, emails=emails, settings=settings)
    if schema:
        with management.begin() as connection:
            connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        management.dispose()


def login(env, email="master@school.test", password=PASSWORD):
    response = env.client.post("/api/v1/auth/login", json={"email": email, "password": password})
    assert response.status_code == 200, response.text
    return response.json()["tokens"]["accessToken"]


def last_token(env):
    body = env.emails[-1]["body"]
    return re.search(r"token=([A-Za-z0-9_-]+)", body).group(1)


def staff_body(email="staff@school.test"):
    return {"displayName": "Staff applicant", "email": email, "password": PASSWORD,
            "requestedRole": "admin", "context": "Institutional staff"}


def test_origin_cookie_and_instant_logout(identity_env):
    env = identity_env
    denied = env.client.post("/api/v1/auth/login", headers={"Origin": "https://evil.test"},
                             json={"email": "master@school.test", "password": PASSWORD})
    assert denied.status_code == 403
    response = env.client.post("/api/v1/auth/login", json={"email": "MASTER@SCHOOL.TEST", "password": PASSWORD})
    assert response.status_code == 200
    cookie = response.headers["set-cookie"]
    assert "HttpOnly" in cookie and "Secure" in cookie and "SameSite=strict" in cookie
    access = response.json()["tokens"]["accessToken"]
    assert "refreshToken" not in response.text
    assert env.client.get("/api/v1/users/me", headers={"Authorization": f"Bearer {access}"}).status_code == 200
    assert env.client.post("/api/v1/auth/logout", json={}).status_code == 204
    assert env.client.get("/api/v1/users/me", headers={"Authorization": f"Bearer {access}"}).status_code == 401


def test_refresh_rotation_replay_revokes_entire_family(identity_env):
    env = identity_env
    old_access = login(env)
    old_refresh = env.client.cookies.get(REFRESH_COOKIE)
    response = env.client.post("/api/v1/auth/refresh", json={})
    assert response.status_code == 200
    new_access = response.json()["tokens"]["accessToken"]
    new_refresh = env.client.cookies.get(REFRESH_COOKIE)
    assert new_refresh != old_refresh
    replay = env.client.post("/api/v1/auth/refresh", json={}, headers={"Cookie": f"{REFRESH_COOKIE}={old_refresh}"})
    assert replay.status_code == 401
    assert replay.json()["error"]["code"] == "SESSION_REPLAY"
    for access in (old_access, new_access):
        assert env.client.get("/api/v1/users/me", headers={"Authorization": f"Bearer {access}"}).status_code == 401
    with env.db() as db:
        sessions = db.scalars(select(RefreshSession)).all()
        assert len(sessions) == 2 and all(x.revoked_at for x in sessions)
        assert all(x.token_hash not in (old_refresh, new_refresh) for x in sessions)


def test_missing_origin_is_rejected_even_with_valid_cookie(identity_env):
    env = identity_env
    login(env)
    env.client.headers.pop("origin")
    response = env.client.post("/api/v1/auth/refresh", json={})
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "ORIGIN_NOT_ALLOWED"


def test_staff_registration_never_grants_role_and_duplicate_preserves_password(identity_env):
    env = identity_env
    body = staff_body()
    assert env.client.post("/api/v1/auth/register", json=body).status_code == 202
    verify = last_token(env)
    assert env.client.post("/api/v1/auth/verify-email", json={"token": verify}).status_code == 204
    response = env.client.post("/api/v1/auth/login", json={"email": body["email"], "password": PASSWORD})
    assert response.status_code == 403 and response.json()["error"]["code"] == "ACCESS_PENDING"
    assert REFRESH_COOKIE not in env.client.cookies
    with env.db() as db:
        user = db.scalar(select(User).where(User.email == body["email"]))
        original_hash = user.password_hash
        assert user.role == "pending" and not user.is_master and not user.is_active and user.email_verified
    body["password"] = "Different password! 77"
    assert env.client.post("/api/v1/auth/register", json=body).status_code == 202
    assert len(env.emails) == 1
    with env.db() as db:
        user = db.scalar(select(User).where(User.email == body["email"]))
        assert user.password_hash == original_hash
    body["isMaster"] = True
    assert env.client.post("/api/v1/auth/register", json=body).status_code == 422


def test_student_career_comes_from_roster_and_no_personal_data_leaks(identity_env):
    env = identity_env
    assert env.client.post("/api/v1/student/register", json={"email": "student@school.test", "password": PASSWORD}).status_code == 202
    response = env.client.post("/api/v1/auth/login", json={"email": "student@school.test", "password": PASSWORD})
    assert response.status_code == 403 and response.json()["error"]["code"] == "EMAIL_NOT_VERIFIED"
    assert env.client.post("/api/v1/auth/verify-email", json={"token": last_token(env)}).status_code == 204
    token = login(env, "student@school.test")
    headers = {"Authorization": f"Bearer {token}"}
    profile = env.client.get("/api/v1/users/me", headers=headers).json()
    assert profile["role"] == "user" and profile["academic"]["careerId"] == "ENG"
    assert profile["academic"]["groupId"] == "G1" and profile["academic"]["verified"] is True
    assert profile["displayName"] == "Student Example"
    assert env.client.get("/api/v1/admin/users", headers=headers).status_code == 403
    assert env.client.get("/api/v1/businesses/local/orders/active", headers=headers).status_code == 403
    assert "password" not in str(profile).lower() and "token" not in str(profile).lower()


def test_unknown_email_and_staff_roster_cannot_self_assign_student(identity_env):
    env = identity_env
    with env.db.begin() as db:
        import_roster_csv(db, COLUMNS + "staff@school.test,E-100,Staff Person,staff,,,,,true\n", "authorized-staff-list")
    for email in ("guess-eng@school.test", "staff@school.test", "student@evil.test"):
        response = env.client.post("/api/v1/student/register", json={"email": email, "password": PASSWORD})
        assert response.status_code == 202 and response.json() == {"status": "received"}
    assert not env.emails
    with env.db() as db:
        assert db.scalar(select(func.count()).select_from(User)) == 2
    response = env.client.post("/api/v1/student/register", json={"email": "student@school.test", "password": PASSWORD, "careerId": "FAKE"})
    assert response.status_code == 422


def test_revoked_roster_cancels_existing_student_session(identity_env):
    env = identity_env
    env.client.post("/api/v1/student/register", json={"email": "student@school.test", "password": PASSWORD})
    env.client.post("/api/v1/auth/verify-email", json={"token": last_token(env)})
    access = login(env, "student@school.test")
    with env.db.begin() as db:
        import_roster_csv(db, ROSTER.replace(",true", ",false"), "revocation-authorized")
    assert env.client.get("/api/v1/users/me", headers={"Authorization": f"Bearer {access}"}).status_code == 401
    response = env.client.post("/api/v1/auth/login", json={"email": "student@school.test", "password": PASSWORD})
    assert response.status_code == 403


def test_reset_token_is_hashed_one_use_and_revokes_access(identity_env):
    env = identity_env
    access = login(env)
    assert env.client.post("/api/v1/auth/forgot-password", json={"email": "master@school.test"}).status_code == 204
    raw = last_token(env)
    assert "/#/reset-password?token=" in env.emails[-1]["body"]
    with env.db() as db:
        record = db.scalar(select(VerificationToken).where(VerificationToken.purpose == "reset"))
        assert record.token_hash != raw and len(record.token_hash) == 64
    new_password = "  New unchanged spaces  "
    assert env.client.post("/api/v1/auth/reset-password", json={"token": raw, "newPassword": new_password}).status_code == 204
    assert env.client.get("/api/v1/users/me", headers={"Authorization": f"Bearer {access}"}).status_code == 401
    assert env.client.post("/api/v1/auth/reset-password", json={"token": raw, "newPassword": PASSWORD}).status_code == 422
    assert env.client.post("/api/v1/auth/login", json={"email": "master@school.test", "password": PASSWORD}).status_code == 401
    login(env, password=new_password)


def test_email_verification_expiry_and_resend(identity_env):
    env = identity_env
    env.client.post("/api/v1/auth/register", json=staff_body())
    old = last_token(env)
    with env.db.begin() as db:
        record = db.scalar(select(VerificationToken))
        record.expires_at = utcnow() - timedelta(seconds=1)
    assert env.client.post("/api/v1/auth/verify-email", json={"token": old}).status_code == 422
    assert env.client.post("/api/v1/auth/resend-verification", json={"email": "staff@school.test"}).status_code == 202
    new = last_token(env)
    assert new != old
    assert env.client.post("/api/v1/auth/verify-email", json={"token": new}).status_code == 204
    assert env.client.post("/api/v1/auth/verify-email", json={"token": new}).status_code == 422


def test_mail_unavailable_fails_closed_and_no_fake_capabilities(identity_env):
    env = identity_env
    env.settings.smtp_host = ""
    options = env.client.get("/api/v1/auth/options").json()
    assert options == {"passwordLogin": True, "selfRegistration": False, "googleEnabled": False}
    assert env.client.post("/api/v1/auth/register", json=staff_body()).status_code == 503
    assert env.client.post("/api/v1/student/register", json={"email": "student@school.test", "password": PASSWORD}).status_code == 503
    assert env.client.post("/api/v1/auth/forgot-password", json={"email": "missing@school.test"}).status_code == 503
    assert env.client.get("/api/v1/auth/google/start").status_code == 503
    with env.db() as db:
        assert db.scalar(select(func.count()).select_from(User)) == 2


def test_failed_mail_delivery_rolls_back_pending_identity(identity_env):
    from snackup.errors import ApiError
    env = identity_env
    def failed(*_):
        raise ApiError(503, "EMAIL_UNAVAILABLE", "SMTP failed")
    env.app.state.mailer = failed
    assert env.client.post("/api/v1/auth/register", json=staff_body()).status_code == 503
    with env.db() as db:
        assert db.scalar(select(User).where(User.email == "staff@school.test")) is None
        assert db.scalar(select(func.count()).select_from(AccessRequest)) == 0
        assert db.scalar(select(func.count()).select_from(VerificationToken)) == 0


def test_roster_import_is_atomic_and_does_not_guess_or_reassign_identity(identity_env):
    env = identity_env
    conflict = COLUMNS + "new@school.test,S-2,New Student,student,NEW,New career,G2,Second,true\n" + \
        "different@school.test,S-100,Conflict,student,ENG,Engineering,G1,First group,true\n"
    with env.db.begin() as db:
        with pytest.raises(ValueError):
            import_roster_csv(db, conflict, "authorized-but-conflicting")
        assert db.get(Career, "NEW") is None
        assert db.scalar(select(AcademicRecord).where(AcademicRecord.email == "new@school.test")) is None
    malformed = COLUMNS + "new@school.test,S-2,New Student,student,,,,,true\n"
    with env.db.begin() as db, pytest.raises(ValueError):
        import_roster_csv(db, malformed, "authorized")


def test_verification_page_has_no_get_side_effect_or_url_token_query(identity_env):
    env = identity_env
    env.client.post("/api/v1/auth/register", json=staff_body())
    assert "/api/v1/auth/verify-email#token=" in env.emails[-1]["body"]
    page = env.client.get("/api/v1/auth/verify-email")
    assert page.status_code == 200
    assert "script-src 'nonce-" in page.headers["content-security-policy"]
    assert "history.replaceState" in page.text and "Confirmar correo" in page.text
    with env.db() as db:
        assert not db.scalar(select(User).where(User.email == "staff@school.test")).email_verified


def test_auth_rate_limit_preserves_generic_errors(identity_env):
    env = identity_env
    for _ in range(10):
        assert env.client.post("/api/v1/auth/login", json={"email": "unknown@school.test", "password": PASSWORD}).status_code == 401
    response = env.client.post("/api/v1/auth/login", json={"email": "unknown@school.test", "password": PASSWORD})
    assert response.status_code == 429 and "retry-after" in response.headers


@pytest.mark.skipif(not os.environ.get("SNACKUP_TEST_DATABASE_URL"), reason="PostgreSQL row locking test")
def test_simultaneous_refresh_cannot_issue_two_live_sessions(identity_env):
    from threading import Barrier
    env = identity_env
    login(env)
    old = env.client.cookies.get(REFRESH_COOKIE)
    barrier = Barrier(2)
    def rotate(_):
        barrier.wait(timeout=10)
        return env.client.post("/api/v1/auth/refresh", json={}, headers={"Cookie": f"{REFRESH_COOKIE}={old}"})
    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(rotate, range(2)))
    assert sorted(response.status_code for response in results) == [200, 401]
    successful = next(response for response in results if response.status_code == 200)
    token = successful.json()["tokens"]["accessToken"]
    assert env.client.get("/api/v1/users/me", headers={"Authorization": f"Bearer {token}"}).status_code == 401
    with env.db() as db:
        assert db.scalar(select(func.count()).select_from(RefreshSession).where(RefreshSession.revoked_at.is_(None))) == 0


def test_authoritative_inactive_staff_revokes_access_without_changing_assigned_role(identity_env):
    env = identity_env
    access = login(env, "operator@school.test")
    headers = {"Authorization": f"Bearer {access}"}
    with env.db.begin() as db:
        import_roster_csv(db, COLUMNS + "operator@school.test,E-200,Operator,staff,,,,,true\n", "authorized-staff")
    assert env.client.get("/api/v1/users/me", headers=headers).status_code == 200
    with env.db.begin() as db:
        import_roster_csv(db, COLUMNS + "operator@school.test,E-200,Operator,staff,,,,,false\n", "authorized-staff-departure")
    assert env.client.get("/api/v1/users/me", headers=headers).status_code == 401
    response = env.client.post("/api/v1/auth/login", json={"email": "operator@school.test", "password": PASSWORD})
    assert response.status_code == 403 and response.json()["error"]["code"] == "ACCESS_REVOKED"
    with env.db() as db:
        user = db.get(User, "operator")
        assert user.role == "business" and user.business_id == "local" and user.is_active
        with pytest.raises(ApiError) as blocked:
            verify_access_token(access, db, env.settings)
        assert blocked.value.status == 401
    # Missing staff data continues to allow the manually approved master.
    login(env)


def test_staff_roster_status_is_checked_even_without_prior_session_revocation(identity_env):
    env = identity_env
    access = login(env)
    with env.db.begin() as db:
        db.add(AcademicRecord(email="master@school.test", institutional_id="E-0", display_name="Master",
                              kind="staff", is_active=False, source="authoritative-direct-update"))
    response = env.client.get("/api/v1/users/me", headers={"Authorization": f"Bearer {access}"})
    assert response.status_code == 403 and response.json()["error"]["code"] == "ACCESS_REVOKED"
    with env.db() as db, pytest.raises(ApiError) as blocked:
        verify_access_token(access, db, env.settings)
    assert blocked.value.code == "ACCESS_REVOKED"


def test_account_recheck_reloads_a_stale_roster_identity_map(identity_env):
    env = identity_env
    with env.db.begin() as db:
        db.add(AcademicRecord(email="master@school.test", institutional_id="E-0", display_name="Master",
                              kind="staff", is_active=True, source="authoritative-test"))
    with env.db() as db:
        user = db.get(User, "master")
        roster = db.scalar(select(AcademicRecord).where(AcademicRecord.email == user.email))
        ensure_account(user, db)
        assert roster.is_active
        # Separate committed update emulates eligibility changing between initial
        # bearer validation and a write's post-User-lock authorization check.
        with env.db.begin() as other:
            other.scalar(select(AcademicRecord).where(AcademicRecord.email == user.email)).is_active = False
        with pytest.raises(ApiError) as blocked:
            ensure_account(user, db)
        assert blocked.value.code == "ACCESS_REVOKED" and not roster.is_active


@pytest.mark.skipif(not os.environ.get("SNACKUP_TEST_DATABASE_URL"), reason="PostgreSQL row locking test")
def test_approval_waits_for_user_before_locking_access_request(identity_env):
    from threading import Event
    env = identity_env
    token = login(env)
    env.client.post("/api/v1/auth/register", json=staff_body())
    with env.db() as db:
        pending = db.scalar(select(User).where(User.email == "staff@school.test"))
        pending_id = pending.id
        access_id = db.scalar(select(AccessRequest.id).where(AccessRequest.user_id == pending_id))
    waiting = Event()
    def observe(_connection, _cursor, statement, parameters, _context, _many):
        if "FOR UPDATE" in statement and "FROM users" in statement and pending_id in parameters.values():
            waiting.set()
    event.listen(env.app.state.db.engine, "before_cursor_execute", observe)
    body = {"decision": "approve", "role": "admin", "businessId": None,
            "identityConfirmed": True, "note": "Authorized staff", "expectedVersion": 1}
    try:
        with ThreadPoolExecutor(max_workers=1) as executor:
            with env.db.begin() as verifier:
                user = verifier.scalar(select(User).where(User.id == pending_id).with_for_update())
                waiting.clear()
                future = executor.submit(env.client.post, f"/api/v1/admin/access-requests/{access_id}/decision",
                                         json=body, headers={"Authorization": f"Bearer {token}"})
                assert waiting.wait(10), "Approval did not reach the pending account lock"
                # If approval locked this child first, NOWAIT fails immediately.
                access = verifier.scalar(select(AccessRequest).where(AccessRequest.id == access_id).with_for_update(nowait=True))
                user.email_verified = access.email_verified = True
                user.version += 1
                access.version += 1
            response = future.result(timeout=10)
        assert response.status_code == 409 and response.json()["error"]["code"] == "VERSION_CONFLICT"
        body["expectedVersion"] = 2
        assert env.client.post(f"/api/v1/admin/access-requests/{access_id}/decision", json=body,
                               headers={"Authorization": f"Bearer {token}"}).status_code == 200
    finally:
        event.remove(env.app.state.db.engine, "before_cursor_execute", observe)


@pytest.mark.skipif(not os.environ.get("SNACKUP_TEST_DATABASE_URL"), reason="PostgreSQL row locking test")
def test_roster_import_waits_for_user_before_locking_academic_record(identity_env):
    from threading import Event
    env = identity_env
    env.client.post("/api/v1/student/register", json={"email": "student@school.test", "password": PASSWORD})
    with env.db() as db:
        student_id = db.scalar(select(User.id).where(User.email == "student@school.test"))
    waiting = Event()
    def observe(_connection, _cursor, statement, parameters, _context, _many):
        if "FOR UPDATE" in statement and "FROM users" in statement and student_id in parameters.values():
            waiting.set()
    def import_departure():
        with env.db.begin() as db:
            return import_roster_csv(db, ROSTER.replace(",true", ",false"), "authorized-departure")
    event.listen(env.app.state.db.engine, "before_cursor_execute", observe)
    try:
        with ThreadPoolExecutor(max_workers=1) as executor:
            with env.db.begin() as purchase:
                purchase.scalar(select(User).where(User.id == student_id).with_for_update())
                waiting.clear()
                future = executor.submit(import_departure)
                assert waiting.wait(10), "Import did not reach the existing account lock"
                record = purchase.scalar(select(AcademicRecord).where(AcademicRecord.email == "student@school.test")
                                          .with_for_update(nowait=True))
                assert record.is_active
            assert future.result(timeout=10)["updated"] == 1
    finally:
        event.remove(env.app.state.db.engine, "before_cursor_execute", observe)
