"""SQL-backed authorization, academic snapshots and administrative atomicity.

The fixture substitutes identity lookup, not permission dependencies or SQL.
JWT/password integration is covered by the complete-app tests.
"""

from datetime import timedelta
from decimal import Decimal
import os
from types import SimpleNamespace
from urllib.parse import quote
from uuid import uuid4

from fastapi import Depends, FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.testclient import TestClient
from jsonschema import Draft202012Validator, FormatChecker
import pytest
from sqlalchemy import create_engine, func, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from snackup import admin
from snackup.admin_models import AccessDecision, Followup, FollowupEvent, Review
from snackup.auth import current_user
from snackup.common import contract
from snackup.config import Settings
from snackup.db import Base, Database, get_db, utcnow
from snackup.errors import ApiError
from snackup.identity_models import AcademicGroup, AcademicRecord, AccessRequest, Career, RefreshSession, User
from snackup.operation_models import Business, Order
from snackup.main import create_app


def assert_schema(name, body):
    spec = contract()
    Draft202012Validator({"$ref": f"#/components/schemas/{name}", "components": spec["components"]},
                         format_checker=FormatChecker()).validate(body)


@pytest.fixture
def admin_api(tmp_path, monkeypatch):
    database_url = os.environ.get('SNACKUP_TEST_DATABASE_URL')
    schema = None
    if database_url:
        schema = 'test_admin_' + uuid4().hex
        management = create_engine(database_url)
        with management.begin() as connection:
            connection.execute(text(f'CREATE SCHEMA "{schema}"'))
        database_url += ('&' if '?' in database_url else '?') + 'options=' + quote('-c search_path=' + schema)
    else:
        database_url = 'sqlite:///' + (tmp_path / 'admin.db').as_posix()
    settings = Settings(environment="test", database_url=database_url,
                        secret_key="test-only-" * 8, public_origin="http://testserver",
                        admin_email_domains="university.test", institution_id="uni", institution_name="University",
                        cafeteria_id="cafe", cafeteria_name="Cafetería", media_dir=tmp_path / 'media', background_events=False)
    app = create_app(settings)
    database = app.state.db
    Base.metadata.create_all(database.engine)
    sent = []
    monkeypatch.setattr(admin, "queue_verification", lambda db, user, settings, mailer=None: sent.append(user.email))

    def identity(request: Request, db: Session = Depends(get_db, scope="function")):
        user = db.get(User, request.headers.get("x-test-user", ""))
        if user is None:
            raise ApiError(401, "UNAUTHENTICATED")
        return user

    app.dependency_overrides[current_user] = identity
    with database.sessions.begin() as db:
        db.add_all([
            Business(id="b1", name="Local 1", cafeteria_id="cafe", cafeteria_name="Cafetería", is_open=True),
            Business(id="b2", name="Local 2", cafeteria_id="cafe", cafeteria_name="Cafetería"),
            Business(id="b3", name="Local retirado", cafeteria_id="cafe", cafeteria_name="Cafetería", is_active=False),
            Career(id="c1", name="Software"), Career(id="c2", name="Mecánica", is_active=False),
        ])
        db.flush()
        db.add(AcademicGroup(id="g1", career_id="c1", name="SW-1"))
        db.flush()
        db.add_all([
            User(id="master", email="master@university.test", display_name="Master", role="admin", is_master=True,
                 is_active=True, approval_status="approved", email_verified=True, password_hash="unused", auth_version=1),
            User(id="admin", email="admin@university.test", display_name="Admin", role="admin",
                 is_active=True, approval_status="approved", email_verified=True, password_hash="unused", auth_version=1),
            User(id="operator", email="operator@example.test", display_name="Operator", role="business", business_id="b1",
                 is_active=True, approval_status="approved", email_verified=True, password_hash="unused", auth_version=1),
            User(id="student", email="student@university.test", display_name="Student", role="user",
                 is_active=True, approval_status="approved", email_verified=True, password_hash="unused", auth_version=1),
            User(id="other-student", email="other@university.test", display_name="Other", role="user",
                 is_active=True, approval_status="approved", email_verified=True, password_hash="unused", auth_version=1),
            User(id="pending", email="pending@university.test", display_name="Pending", role="pending",
                 is_active=False, approval_status="pending", email_verified=False, password_hash="unused", auth_version=1),
            AcademicRecord(id="ar1", email="student@university.test", institutional_id="0001", display_name="Student",
                           kind="student", career_id="c1", group_id="g1", source="authorized-test-roster"),
        ])
        db.flush()
        db.add(AccessRequest(id="request", user_id="pending", email="pending@university.test", display_name="Pending",
                             requested_role="business", request_context="Operate cafe", email_verified=False))
        db.add(Order(id="complete", student_id="student", business_id="b1", order_number=1,
                      customer_name="Student", status="completed", total=Decimal("25.00"), pickup_code="AB1234",
                      completed_at=utcnow()))
        db.add(Order(id="active", student_id="student", business_id="b1", order_number=2,
                      customer_name="Student", status="pending", total=Decimal("25.00"), pickup_code="CD5678"))
    with TestClient(app) as client:
        yield SimpleNamespace(client=client, db=database, sent=sent, settings=settings)
    database.dispose()
    if schema:
        with management.begin() as connection:
            connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        management.dispose()


def headers(actor="master"):
    return {"x-test-user": actor}


def decision(**changes):
    return {"decision": "approve", "role": "business", "businessId": "b2", "identityConfirmed": True,
            "note": "Identity confirmed", "expectedVersion": 1, **changes}


def user_create(**changes):
    return {"displayName": "New operator", "email": "new@example.test", "password": "private-test-password",
            "role": "business", "businessId": "b2", "isActive": True, **changes}


def user_update(**changes):
    return {"displayName": "Operator", "email": "operator@example.test", "role": "business", "businessId": "b1",
            "isActive": True, "expectedVersion": 1, **changes}


def followup(**changes):
    return {"status": "in_review", "assignee": "Supervisor", "note": "Investigating", "expectedVersion": 0, **changes}


def create_review(api):
    response = api.client.post("/api/legacy/v1/student/orders/complete/review", headers=headers("student"),
                               json={"rating": 4, "comment": "Good lunch"})
    assert response.status_code == 201, response.text
    return response.json()


def test_account_management_is_master_only(admin_api):
    for actor, status in (("master", 200), ("admin", 403), ("operator", 403), ("student", 403)):
        response = admin_api.client.get("/api/legacy/v1/admin/users", headers=headers(actor))
        assert response.status_code == status
        if status == 200:
            assert_schema("UserPage", response.json())
            assert "password" not in response.text.lower()
    assert admin_api.client.get("/api/legacy/v1/institution").status_code == 401
    for path in ("businesses", "reviews", "followups", "academic-catalog", "access-requests"):
        assert admin_api.client.get(f"/api/legacy/v1/admin/{path}", headers=headers("operator")).status_code == 403


def test_institution_and_catalog_keep_real_references(admin_api):
    response = admin_api.client.get("/api/legacy/v1/institution", headers=headers("student"))
    assert_schema("Institution", response.json())
    assert response.json()["adminEmailDomains"] == ["university.test"]
    entries = []
    for page in (1, 2):
        response = admin_api.client.get(f"/api/legacy/v1/admin/academic-catalog?page={page}&limit=2", headers=headers("admin"))
        assert_schema("AcademicEntryPage", response.json())
        assert response.json()["pagination"]["total"] == 3
        entries.extend(response.json()["data"])
    assert len({x["id"] for x in entries}) == 3
    assert {"id": "g1", "kind": "group", "name": "SW-1", "careerId": "c1"} in entries
    assert {"id": "c2", "kind": "career", "name": "Mecánica"} in entries
    assert admin_api.client.get("/api/legacy/v1/admin/academic-catalog?limit=201", headers=headers("admin")).status_code == 422


def test_new_local_closed_and_admin_update_version_and_pending_protection(admin_api):
    body = {"name": "Nuevo", "category": "Comida", "description": "Almuerzos", "cafeteriaId": "cafe",
            "isActive": True, "timezone": "America/Mexico_City"}
    response = admin_api.client.post("/api/legacy/v1/admin/businesses", headers=headers("admin"), json=body)
    assert response.status_code == 201
    assert_schema("Business", response.json())
    assert response.json()["isOpen"] is False
    assert admin_api.client.post("/api/legacy/v1/admin/businesses", headers=headers("admin"),
                                 json={**body, "cafeteriaId": "foreign"}).status_code == 422
    update = {"name": "Local renamed", "category": "Food", "description": "Lunch", "isActive": False, "expectedVersion": 1}
    response = admin_api.client.patch("/api/legacy/v1/admin/businesses/b1", headers=headers("admin"), json=update)
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "BUSINESS_HAS_ACTIVE_ORDERS"
    with admin_api.db.sessions() as db:
        assert db.get(Business, "b1").is_open is True
        assert db.get(Business, "b1").version == 1
    response = admin_api.client.patch("/api/legacy/v1/admin/businesses/b2", headers=headers("admin"), json=update)
    assert response.status_code == 200
    assert response.json()["version"] == 2 and response.json()["isActive"] is False
    assert admin_api.client.patch("/api/legacy/v1/admin/businesses/b2", headers=headers("admin"), json=update).status_code == 409


def test_master_creates_verified_later_user_and_rejects_promotion_or_invalid_domain(admin_api):
    response = admin_api.client.post("/api/legacy/v1/admin/users", headers=headers(), json=user_create())
    assert response.status_code == 201, response.text
    assert_schema("User", response.json())
    assert response.json()["isMaster"] is False
    assert admin_api.sent == ["new@example.test"]
    with admin_api.db.sessions() as db:
        user = db.get(User, response.json()["id"])
        assert user.email_verified is False
        assert user.password_hash.startswith("$argon2")
    duplicate = admin_api.client.post("/api/legacy/v1/admin/users", headers=headers(), json=user_create())
    assert duplicate.status_code == 409 and duplicate.json()["error"]["code"] == "EMAIL_EXISTS"
    invalid = admin_api.client.post("/api/legacy/v1/admin/users", headers=headers(),
                                    json=user_create(email="admin@university.test.evil.test", role="admin", businessId=None))
    assert invalid.status_code == 422 and invalid.json()["error"]["code"] == "INSTITUTIONAL_EMAIL_REQUIRED"
    assert admin_api.client.post("/api/legacy/v1/admin/users", headers=headers(),
                                 json=user_create(email="bad address@university.test", role="admin", businessId=None)).status_code == 422
    assert admin_api.client.post("/api/legacy/v1/admin/users", headers=headers(),
                                 json=user_create(isMaster=True)).status_code == 422


def test_active_operator_assignment_and_database_constraint(admin_api):
    response = admin_api.client.post("/api/legacy/v1/admin/users", headers=headers(), json=user_create(businessId="b1"))
    assert response.status_code == 409 and response.json()["error"]["code"] == "BUSINESS_ALREADY_ASSIGNED"
    response = admin_api.client.post("/api/legacy/v1/admin/users", headers=headers(), json=user_create(businessId="b1", isActive=False))
    assert response.status_code == 201
    activate = user_update(displayName="New operator", email="new@example.test", businessId="b1")
    response = admin_api.client.patch(f"/api/legacy/v1/admin/users/{response.json()['id']}", headers=headers(), json=activate)
    assert response.status_code == 409
    # A database constraint remains effective even if a future caller skips the precheck.
    with pytest.raises(IntegrityError), admin_api.db.sessions.begin() as db:
        db.add(User(id="collision", email="collision@example.test", display_name="Collision", password_hash="unused",
                    role="business", business_id="b1", is_active=True, approval_status="approved"))
        db.flush()


def test_access_requires_verified_email_and_identity_then_audits_atomically(admin_api):
    response = admin_api.client.get("/api/legacy/v1/admin/access-requests", headers=headers())
    assert_schema("AccessRequestPage", response.json())
    response = admin_api.client.post("/api/legacy/v1/admin/access-requests/request/decision", headers=headers(), json=decision())
    assert response.status_code == 422 and response.json()["error"]["code"] == "EMAIL_NOT_VERIFIED"
    with admin_api.db.sessions.begin() as db:
        db.get(User, "pending").email_verified = True
        db.get(AccessRequest, "request").email_verified = True
    response = admin_api.client.post("/api/legacy/v1/admin/access-requests/request/decision", headers=headers(),
                                     json=decision(identityConfirmed=False))
    assert response.status_code == 422
    response = admin_api.client.post("/api/legacy/v1/admin/access-requests/request/decision", headers=headers(), json=decision())
    assert response.status_code == 200
    assert_schema("DecisionResult", response.json())
    with admin_api.db.sessions() as db:
        assert db.get(User, "pending").role == "business"
        assert db.get(User, "pending").business_id == "b2"
        audit = db.scalar(select(AccessDecision))
        assert audit.actor_id == "master" and audit.decision == "approve"
        assert db.get(AccessRequest, "request").reviewed_by == "master"
    retry = admin_api.client.post("/api/legacy/v1/admin/access-requests/request/decision", headers=headers(), json=decision())
    assert retry.status_code == 409 and retry.json()["error"]["code"] == "REQUEST_ALREADY_REVIEWED"
    assert admin_api.client.get("/api/legacy/v1/admin/access-requests", headers=headers()).json()["data"] == []


def test_rejected_request_never_receives_operational_access(admin_api):
    response = admin_api.client.post("/api/legacy/v1/admin/access-requests/request/decision", headers=headers(),
                                     json=decision(decision="reject", identityConfirmed=False))
    assert response.status_code == 200
    assert_schema("DecisionResult", response.json())
    assert response.json()["role"] == "pending" and response.json()["isActive"] is False
    with admin_api.db.sessions() as db:
        assert db.get(User, "pending").approval_status == "rejected"
        assert db.scalar(select(func.count()).select_from(AccessDecision)) == 1


def test_failed_assignment_does_not_consume_request_or_write_audit(admin_api):
    with admin_api.db.sessions.begin() as db:
        db.get(User, "pending").email_verified = True
        db.get(AccessRequest, "request").email_verified = True
    response = admin_api.client.post("/api/legacy/v1/admin/access-requests/request/decision", headers=headers(),
                                     json=decision(businessId="b1"))
    assert response.status_code == 409
    with admin_api.db.sessions() as db:
        assert db.get(User, "pending").role == "pending"
        assert db.get(AccessRequest, "request").version == 1
        assert db.scalar(select(func.count()).select_from(AccessDecision)) == 0


def test_pending_patch_and_master_demotion_forbidden(admin_api):
    response = admin_api.client.patch("/api/legacy/v1/admin/users/pending", headers=headers(),
                                      json=user_update(email="pending@university.test", businessId="b2"))
    assert response.status_code == 409 and response.json()["error"]["code"] == "APPROVAL_REQUIRED"
    response = admin_api.client.patch("/api/legacy/v1/admin/users/master", headers=headers(),
                                      json=user_update(email="master@university.test", isActive=False))
    assert response.status_code == 403 and response.json()["error"]["code"] == "MASTER_PROTECTED"
    with admin_api.db.sessions() as db:
        assert db.get(User, "master").is_active is True


def test_changed_email_clears_verification_and_revokes_sessions(admin_api):
    with admin_api.db.sessions.begin() as db:
        db.add(RefreshSession(id="session", user_id="operator", family_id="family", token_hash="x" * 64,
                               auth_version=1, expires_at=utcnow() + timedelta(days=1)))
    response = admin_api.client.patch("/api/legacy/v1/admin/users/operator", headers=headers(),
                                      json=user_update(email="updated@example.test"))
    assert response.status_code == 200, response.text
    assert_schema("User", response.json())
    with admin_api.db.sessions() as db:
        user = db.get(User, "operator")
        assert user.auth_version == 2 and user.version == 2
        assert user.email_verified is False
        assert db.get(RefreshSession, "session").revoked_at is not None
    assert admin_api.sent == ["updated@example.test"]


def test_followup_creation_conflicts_and_immutable_history(admin_api):
    review = create_review(admin_api)
    path = f"/api/legacy/v1/admin/reviews/{review['id']}/followup"
    response = admin_api.client.get(path, headers=headers("admin"))
    assert response.status_code == 404 and response.json()["error"]["code"] == "FOLLOWUP_NOT_FOUND"
    missing = admin_api.client.get("/api/legacy/v1/admin/reviews/missing/followup", headers=headers("admin"))
    assert missing.json()["error"]["code"] == "REVIEW_NOT_FOUND"
    empty = admin_api.client.get(path + "/history", headers=headers("admin"))
    assert_schema("FollowupPage", empty.json())
    assert empty.json()["data"] == []
    first = admin_api.client.put(path, headers=headers("admin"), json=followup())
    assert first.status_code == 200
    assert_schema("Followup", first.json())
    assert first.json()["version"] == 1
    assert admin_api.client.put(path, headers=headers(), json=followup()).status_code == 409
    second = admin_api.client.put(path, headers=headers(), json=followup(status="resolved", note="Resolved", expectedVersion=1))
    assert second.status_code == 200 and second.json()["version"] == 2
    response = admin_api.client.get(path + "/history", headers=headers())
    assert_schema("FollowupPage", response.json())
    assert [(x["version"], x["note"], x["actorId"]) for x in response.json()["data"]] == [(2, "Resolved", "master"), (1, "Investigating", "admin")]
    stale = admin_api.client.put(path, headers=headers(), json=followup(note="Do not persist", expectedVersion=1))
    assert stale.status_code == 409
    with admin_api.db.sessions() as db:
        assert db.get(Followup, review["id"]).note == "Resolved"
        assert db.scalar(select(func.count()).select_from(FollowupEvent)) == 2


def test_invalid_followup_rolls_back_state_and_history(admin_api):
    review = create_review(admin_api)
    path = f"/api/legacy/v1/admin/reviews/{review['id']}/followup"
    response = admin_api.client.put(path, headers=headers("admin"), json=followup(note="   "))
    assert response.status_code == 422
    with admin_api.db.sessions() as db:
        assert db.get(Followup, review["id"]) is None
        assert db.scalar(select(func.count()).select_from(FollowupEvent)) == 0


def test_student_review_ownership_completion_uniqueness_and_forged_academics(admin_api):
    path = "/api/legacy/v1/student/orders/complete/review"
    assert admin_api.client.post(path, headers=headers("admin"), json={"rating": 5}).status_code == 403
    assert admin_api.client.post(path, headers=headers("other-student"), json={"rating": 5}).status_code == 404
    response = admin_api.client.post("/api/legacy/v1/student/orders/active/review", headers=headers("student"), json={"rating": 5})
    assert response.status_code == 409 and response.json()["error"]["code"] == "ORDER_NOT_COMPLETED"
    for data in ({"rating": 5, "careerId": "c2"}, {"rating": True}, {"rating": 0}, {"rating": 5, "foodRating": 0}):
        assert admin_api.client.post(path, headers=headers("student"), json=data).status_code == 422
    create_review(admin_api)
    duplicate = admin_api.client.post(path, headers=headers("student"), json={"rating": 5})
    assert duplicate.status_code == 409 and duplicate.json()["error"]["code"] == "REVIEW_EXISTS"


def test_reviews_snapshot_academics_and_hide_student_identity(admin_api):
    review = create_review(admin_api)
    assert_schema("Review", review)
    assert review["careerId"] == "c1" and review["career"] == "Software"
    assert review["groupId"] == "g1" and review["group"] == "SW-1"
    assert review["foodRating"] is None and review["serviceRating"] is None
    with admin_api.db.sessions.begin() as db:
        db.get(Career, "c1").name = "Renamed career"
        db.get(AcademicRecord, "ar1").career_id = "c2"
        db.get(AcademicRecord, "ar1").group_id = None
    response = admin_api.client.get("/api/legacy/v1/admin/reviews", headers=headers("admin"))
    assert_schema("ReviewPage", response.json())
    assert response.json()["data"][0]["career"] == "Software"
    assert response.json()["data"][0]["group"] == "SW-1"
    assert not ({"email", "displayName", "studentId", "userId", "orderId", "institutionalId"} & response.json()["data"][0].keys())
    followups = admin_api.client.get("/api/legacy/v1/admin/followups", headers=headers("admin"))
    assert_schema("FollowupPage", followups.json())
