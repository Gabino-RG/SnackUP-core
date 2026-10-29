"""V3 administrative transactions and non-escalating account lifecycle."""
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal
from threading import Event

import jwt
import pytest
from sqlalchemy import event, func, select, update

from snackup.db import utcnow
from snackup.errors import ApiError
from snackup.identity_models import AccountAuditEvent, RefreshSession, User
from snackup.operation_models import Business, Order

pytestmark = pytest.mark.v3
PASSWORD = "Test-Only-Password-392!"


def business_body():
    return {"name": "Nuevo local", "category": "Cafetería", "description": "Alta autorizada",
            "timezone": "America/Mexico_City",
            "account": {"email": "new-kitchen@staff.example.edu", "displayName": "Nueva Cocina", "password": PASSWORD}}


def test_v3_admin_provisions_business_and_kitchen_atomically_without_smtp(app, client, tokens):
    app.state.settings.smtp_host = ""
    response = client.post("/api/v1/admin/businesses", json=business_body(), headers=tokens["admin"])
    assert response.status_code == 201
    result = response.json()
    business, user = result["business"], result["user"]
    assert business["ownerId"] == user["id"] and user["businessId"] == business["id"]
    assert user["role"] == "COCINA" and user["emailVerified"]
    assert business["isOpen"] is False and business["isActive"]
    assert business["totalOrders"] == 0 and business["totalRatings"] == 0
    assert "nextOrderNumber" not in business and PASSWORD not in response.text
    with app.state.db.sessions() as db:
        audit = list(db.scalars(select(AccountAuditEvent)))
        assert len(audit) == 2 and all(event.actor_id == "admin" for event in audit)
        assert PASSWORD not in str([event.data for event in audit])
    login = client.post("/api/v1/auth/login", json={"email": business_body()["account"]["email"], "password": PASSWORD})
    assert login.status_code == 200 and login.json()["user"]["role"] == "COCINA"


def test_v3_admin_create_failure_rolls_back_business_and_audit(app, client, tokens, monkeypatch):
    from snackup import v3_admin
    def fail_password(_):
        raise ApiError(503, "CREDENTIAL_SERVICE_UNAVAILABLE")
    monkeypatch.setattr(v3_admin, "hash_password", fail_password)
    response = client.post("/api/v1/admin/businesses", json=business_body(), headers=tokens["admin"])
    assert response.status_code == 503
    with app.state.db.sessions() as db:
        assert db.scalar(select(func.count()).select_from(Business)) == 2
        assert db.scalar(select(User.id).where(User.email == business_body()["account"]["email"])) is None
        assert db.scalar(select(func.count()).select_from(AccountAuditEvent)) == 0


def test_v3_duplicate_kitchen_and_invalid_timezone_do_not_create_local(app, client, tokens):
    body = business_body()
    body["account"]["email"] = "operator@staff.example.edu"
    assert client.post("/api/v1/admin/businesses", json=body, headers=tokens["admin"]).status_code == 409
    body = {**business_body(), "timezone": "Not/A_Real_Zone"}
    assert client.post("/api/v1/admin/businesses", json=body, headers=tokens["admin"]).status_code == 422
    with app.state.db.sessions() as db:
        assert db.scalar(select(func.count()).select_from(Business)) == 2


def test_v3_student_suspension_preserves_role_and_revokes_session(app, client, tokens):
    response = client.patch("/api/v1/admin/users/student", json={"isActive": False, "expectedVersion": 1}, headers=tokens["admin"])
    assert response.status_code == 200
    assert response.json()["role"] == "ALUMNO" and response.json()["isActive"] is False
    assert client.get("/api/v1/users/me", headers=tokens["student"]).status_code == 401
    assert client.get("/api/v1/users/me", headers=tokens["operator"]).status_code == 200
    with app.state.db.sessions() as db:
        assert db.get(User, "student").role == "user"
    promoted = client.patch("/api/v1/admin/users/student", json={"role": "ADMIN", "expectedVersion": 2}, headers=tokens["admin"])
    assert promoted.status_code == 422
    restored = client.patch("/api/v1/admin/users/student", json={"isActive": True, "expectedVersion": 2}, headers=tokens["admin"])
    assert restored.status_code == 200 and restored.json()["role"] == "ALUMNO"


def test_v3_admin_write_conflict_and_protected_master(app, client, tokens):
    assert client.patch("/api/v1/admin/users/student", json={"isActive": False, "expectedVersion": 99}, headers=tokens["admin"]).status_code == 409
    assert client.patch("/api/v1/admin/users/master", json={"isActive": False, "expectedVersion": 1}, headers=tokens["admin"]).status_code == 403
    assert client.patch("/api/v1/admin/users/admin", json={"isActive": False}, headers=tokens["master"]).status_code == 403
    for identity in ("student", "operator"):
        assert client.post("/api/v1/admin/businesses", json=business_body(), headers=tokens[identity]).status_code == 403


def test_v3_soft_delete_blocks_active_orders_and_preserves_history(app, client, tokens):
    with app.state.db.sessions.begin() as db:
        db.add(Order(id="historical-order", business_id="business-1", student_id="student",
                     order_number=1, customer_name="Student", status="ready", total=Decimal("20.00"), pickup_code="ABC123"))
    blocked = client.request("DELETE", "/api/v1/admin/businesses/business-1", json={"expectedVersion": 1}, headers=tokens["admin"])
    assert blocked.status_code == 409 and blocked.json()["error"]["code"] == "BUSINESS_HAS_ACTIVE_ORDERS"
    with app.state.db.sessions.begin() as db:
        assert db.get(Business, "business-1").is_active
        db.get(Order, "historical-order").status = "completed"
    deleted = client.request("DELETE", "/api/v1/admin/businesses/business-1", json={"expectedVersion": 1}, headers=tokens["admin"])
    assert deleted.status_code == 204
    with app.state.db.sessions() as db:
        assert not db.get(Business, "business-1").is_active
        assert db.get(Order, "historical-order").status == "completed"
        assert not db.get(User, "operator").is_active
    assert client.get("/api/v1/users/me", headers=tokens["operator"]).status_code == 401
    assert client.get("/api/v1/users/me", headers=tokens["other-operator"]).status_code == 200


def test_v3_business_metadata_version_and_no_admin_open_switch(app, client, tokens):
    response = client.patch("/api/v1/admin/businesses/business-1", json={"description": "Nueva descripción", "expectedVersion": 1}, headers=tokens["admin"])
    assert response.status_code == 200 and response.json()["version"] == 2
    assert response.json()["description"] == "Nueva descripción"
    assert client.patch("/api/v1/admin/businesses/business-1", json={"name": "Conflict", "expectedVersion": 1}, headers=tokens["admin"]).status_code == 409
    assert client.patch("/api/v1/admin/businesses/business-1", json={"isOpen": True}, headers=tokens["admin"]).status_code == 422
    assert client.get("/api/v1/admin/businesses", headers=tokens["admin"]).status_code == 200


@pytest.mark.postgres
def test_v3_admin_logout_winning_lock_prevents_a_waiting_business_update(app, client, tokens):
    if app.state.db.engine.dialect.name != "postgresql":
        pytest.skip("Real PostgreSQL is required to verify administrative revocation under a row lock")
    bearer = tokens["admin"]["Authorization"].removeprefix("Bearer ")
    sid = jwt.decode(bearer, options={"verify_signature": False})["sid"]
    waiting = Event()

    def before_execute(connection, cursor, statement, parameters, context, many):
        if "FOR UPDATE" in statement and "users" in statement:
            waiting.set()

    # Hold the same User lock as logout and leave its session revocation
    # uncommitted. The admin request authenticates, then must wait on that lock.
    blocker = app.state.db.sessions()
    blocker.scalar(select(User).where(User.id == "admin").with_for_update())
    blocker.execute(update(RefreshSession).where(RefreshSession.id == sid).values(revoked_at=utcnow()))
    event.listen(app.state.db.engine, "before_cursor_execute", before_execute)
    try:
        with ThreadPoolExecutor(max_workers=1) as pool:
            pending = pool.submit(client.patch, "/api/v1/admin/businesses/business-1",
                                  json={"name": "Unauthorized after logout", "expectedVersion": 1},
                                  headers=tokens["admin"])
            try:
                assert waiting.wait(5), "The administrative update did not reach the User lock"
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
        business = db.get(Business, "business-1")
        assert business.name == "Cafetería Uno" and business.version == 1
        assert db.scalar(select(func.count()).select_from(AccountAuditEvent)) == 0
