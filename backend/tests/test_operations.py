"""Real SQL operation tests. Authentication crypto is covered by identity tests.

Only authentication lookup is replaced here; authorization, route validation,
SQL transactions, stock, versions, media decoding and outbox run unchanged.
"""
import io
import os
from datetime import datetime, timezone
from decimal import Decimal
from types import SimpleNamespace
from urllib.parse import quote
from uuid import uuid4

import pytest
from fastapi import Depends, Request
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import create_engine, func, select, text

from snackup.auth import current_user
from snackup.config import Settings
from snackup.db import Base, OutboxEvent, get_db
from snackup.errors import ApiError
from snackup.identity_models import AcademicRecord, Career, User
from snackup.main import create_app
from snackup.operation_models import Business, IdempotencyRecord, Order, OrderItem, OrderTransition, Product


@pytest.fixture
def operations_env(tmp_path):
    database_url = os.environ.get("SNACKUP_TEST_DATABASE_URL")
    schema = None
    if database_url:
        schema = "test_operations_" + uuid4().hex
        management = create_engine(database_url)
        with management.begin() as connection:
            connection.execute(text(f'CREATE SCHEMA "{schema}"'))
        database_url += ("&" if "?" in database_url else "?") + "options=" + quote("-c search_path=" + schema)
    else:
        database_url = "sqlite:///" + str(tmp_path / "operations.sqlite")
    settings = Settings(environment="test", database_url=database_url, pool_size=5, max_overflow=2,
                               secret_key="domain-tests-only-with-no-auth-tokens", redis_url="",
                               public_origin="http://testserver", media_dir=tmp_path / "media",
                               background_events=False)
    app = create_app(settings)
    database = app.state.db
    Base.metadata.create_all(database.engine)
    with database.sessions.begin() as db:
        db.add(Career(id="test-career", name="Test career"))
        db.add_all([Business(id="shop", name="Cocina", cafeteria_id="caf", cafeteria_name="Cafetería", is_open=True),
                    Business(id="other", name="Otro", cafeteria_id="caf", cafeteria_name="Cafetería", is_open=True)])
        db.flush()
        for uid, role, business in (("student", "user", None), ("student2", "user", None),
                                    ("operator", "business", "shop"), ("otherop", "business", "other"),
                                    ("admin", "admin", None)):
            db.add(User(id=uid, email=uid + "@institution.test", display_name=uid, password_hash="not-used",
                        role=role, business_id=business, is_active=True, is_master=uid == "admin",
                        approval_status="approved", email_verified=True))
            if role == "user":
                db.add(AcademicRecord(email=uid + "@institution.test", institutional_id="ID-" + uid,
                                       display_name=uid, kind="student", career_id="test-career",
                                       is_active=True, source="test-authorized-roster"))
        db.add_all([Product(id="meal", business_id="shop", name="Torta", description="", category="Comida",
                            price=Decimal("25.50"), stock=5, is_available=True),
                    Product(id="drink", business_id="shop", name="Agua", description="", category="Bebidas",
                            price=Decimal("10.00"), stock=1, is_available=True),
                    Product(id="unlimited", business_id="shop", name="Café", description="", category="Bebidas",
                            price=Decimal("12.00"), stock=None, is_available=True)])
    def test_user(request: Request, db=Depends(get_db, scope="function")):
        user = db.get(User, request.headers.get("x-user", "student"))
        if user is None:
            raise ApiError(401, "UNAUTHENTICATED")
        return user

    app.dependency_overrides[current_user] = test_user
    with TestClient(app) as client:
        yield SimpleNamespace(client=client, db=database, app=app)
    if schema:
        with management.begin() as connection:
            connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        management.dispose()


def buy(env, items=None, key="order-request-key-0001", **extra):
    return env.client.post("/api/v1/student/orders", headers={"Idempotency-Key": key},
                           json={"businessId": "shop", "items": items or [{"productId": "meal", "quantity": 2}], **extra})


def act(env, order, action, **extra):
    return env.client.post(f"/api/v1/orders/{order['id']}/{action}", headers={"x-user": "operator"},
                           json={"expectedVersion": order["version"], **extra})


def count(db, model):
    return db.scalar(select(func.count()).select_from(model))


def test_creation_reserves_atomically_and_replays_exact_result(operations_env):
    env = operations_env
    first = buy(env)
    assert first.status_code == 201, first.text
    order = first.json()
    assert (order["status"], order["version"], order["total"]) == ("pending", 1, 51.0)
    assert len(order["pickupCode"]) == 8
    assert order["paymentStatus"] == "pay_at_pickup"
    assert buy(env).json() == order
    changed = buy(env, items=[{"productId": "meal", "quantity": 1}])
    assert changed.status_code == 409 and changed.json()["error"]["code"] == "IDEMPOTENCY_CONFLICT"
    with env.db.sessions() as db:
        assert db.get(Product, "meal").stock == 3
        assert db.get(Product, "meal").version == 2
        assert db.get(Business, "shop").next_order_number == 2
        assert count(db, Order) == count(db, IdempotencyRecord) == count(db, OrderTransition) == 1
        assert count(db, OutboxEvent) == 2
        assert all("pickupCode" not in event.data for event in db.scalars(select(OutboxEvent)))


def test_all_or_nothing_stock_failure_and_untrusted_fields(operations_env):
    env = operations_env
    response = buy(env, items=[{"productId": "meal", "quantity": 2}, {"productId": "drink", "quantity": 2}])
    assert response.status_code == 409
    with env.db.sessions() as db:
        assert db.get(Product, "meal").stock == 5
        assert db.get(Product, "drink").stock == 1
        assert db.get(Business, "shop").next_order_number == 1
        assert count(db, Order) == count(db, OutboxEvent) == count(db, IdempotencyRecord) == 0
    assert buy(env, total=0.01).status_code == 422
    assert buy(env, items=[{"productId": "meal", "quantity": True}]).status_code == 422
    assert buy(env, paymentMethod="paid").status_code == 422
    assert env.client.post("/api/v1/student/orders", json={"businessId": "shop", "items": []}).status_code == 422


def test_kitchen_flow_hides_codes_and_rejects_wrong_order_and_stale_version(operations_env):
    env = operations_env
    order = buy(env).json()
    assert env.client.get(f"/api/v1/orders/{order['id']}", headers={"x-user": "otherop"}).status_code == 404
    assert env.client.get(f"/api/v1/orders/{order['id']}", headers={"x-user": "admin"}).status_code == 403
    assert env.client.get(f"/api/v1/student/orders/{order['id']}", headers={"x-user": "student2"}).status_code == 404
    assert act(env, order, "ready").status_code == 409
    code = order["pickupCode"]
    accepted = act(env, order, "accept")
    assert accepted.status_code == 200
    assert "pickupCode" not in accepted.json() and "customerNumeroDeControl" not in accepted.json()
    assert act(env, order, "accept").json()["error"]["code"] == "VERSION_CONFLICT"
    order = accepted.json()
    assert env.client.post(f"/api/v1/student/orders/{order['id']}/cancel", json={"expectedVersion": order["version"]}).status_code == 409
    order = act(env, order, "start").json()
    order = act(env, order, "ready").json()
    assert act(env, order, "cancel", reason="other", notes="motivo").status_code == 409
    assert act(env, order, "complete", method="manual", code="bad").status_code == 422
    assert act(env, order, "complete", method="manual", code="código incorrecto").status_code == 422
    completed = act(env, order, "complete", method="qr", code=code)
    assert completed.status_code == 200
    assert completed.json()["status"] == "completed"
    assert completed.json()["paymentStatus"] == "pay_at_pickup"
    assert act(env, order, "complete", method="qr", code=code).status_code == 409
    active = env.client.get("/api/v1/businesses/shop/orders/active", headers={"x-user": "operator"}).json()
    assert active["data"] == []
    with env.db.sessions() as db:
        assert db.get(Product, "meal").stock == 3
        assert count(db, OrderTransition) == 5


def test_cancellation_returns_stock_once_and_cannot_inflate_newly_enabled_stock(operations_env):
    env = operations_env
    order = buy(env, items=[{"productId": "drink", "quantity": 1}]).json()
    with env.db.sessions() as db:
        assert db.get(Product, "drink").stock == 0
        assert not db.get(Product, "drink").is_available
    cancelled = act(env, order, "cancel", reason="product_unavailable")
    assert cancelled.status_code == 200
    assert act(env, order, "cancel", reason="product_unavailable").status_code == 409
    with env.db.sessions() as db:
        assert db.get(Product, "drink").stock == 1
        assert db.get(Product, "drink").is_available
    unlimited = buy(env, items=[{"productId": "unlimited", "quantity": 3}], key="order-request-key-0002").json()
    with env.db.sessions.begin() as db:
        db.get(Product, "unlimited").stock = 10
    assert act(env, unlimited, "cancel", reason="store_issue").status_code == 200
    with env.db.sessions() as db:
        assert db.get(Product, "unlimited").stock == 10  # originally unreserved quantities are never returned


def test_student_can_cancel_only_own_pending_order(operations_env):
    env = operations_env
    order = buy(env).json()
    url = f"/api/v1/student/orders/{order['id']}/cancel"
    assert env.client.post(url, headers={"x-user": "student2"}, json={"expectedVersion": 1}).status_code == 404
    cancelled = env.client.post(url, json={"expectedVersion": 1})
    assert cancelled.status_code == 200 and cancelled.json()["cancelReason"] == "student_cancelled"
    assert "pickupCode" in cancelled.json()
    with env.db.sessions() as db:
        assert db.get(Product, "meal").stock == 5


def test_catalog_omitted_stock_preserves_snapshot_and_soft_delete(operations_env):
    env = operations_env
    order = buy(env).json()
    body = {"name": "Torta nueva", "description": "", "category": "Comida", "price": 30.25,
            "imageUrl": None, "isAvailable": True, "isFeatured": False, "expectedVersion": 2}
    updated = env.client.patch("/api/v1/products/meal", headers={"x-user": "operator"}, json=body)
    assert updated.status_code == 200, updated.text
    assert updated.json()["stock"] == 3
    deleted = env.client.request("DELETE", "/api/v1/products/meal", headers={"x-user": "operator"},
                                 json={"expectedVersion": 3})
    assert deleted.status_code == 204
    assert env.client.get("/api/v1/products/meal", headers={"x-user": "operator"}).status_code == 404
    historical = env.client.get(f"/api/v1/orders/{order['id']}", headers={"x-user": "operator"}).json()
    assert historical["items"][0]["name"] == "Torta" and historical["total"] == 51.0
    assert act(env, order, "cancel", reason="store_issue").status_code == 200
    with env.db.sessions() as db:
        assert db.get(Product, "meal").stock == 5
        assert db.get(Product, "meal").is_deleted and not db.get(Product, "meal").is_available


def test_null_stock_disables_tracking_and_business_closed_blocks_new_orders(operations_env):
    env = operations_env
    body = {"name": "Torta", "description": "", "category": "Comida", "price": 25.50, "stock": None,
            "imageUrl": None, "isAvailable": True, "isFeatured": False, "expectedVersion": 1}
    assert env.client.patch("/api/v1/products/meal", headers={"x-user": "operator"}, json=body).json()["stock"] is None
    order = buy(env).json()
    closed = env.client.patch("/api/v1/businesses/shop/status", headers={"x-user": "operator"},
                               json={"expectedVersion": 1, "isOpen": False})
    assert closed.status_code == 200
    assert buy(env, key="order-request-key-0002").json()["error"]["code"] == "BUSINESS_CLOSED"
    assert act(env, order, "accept").status_code == 200  # existing orders remain operable


def test_history_uses_local_completion_day_and_full_summary(operations_env):
    env = operations_env
    orders = [buy(env, items=[{"productId": "meal", "quantity": 1}], key=f"history-order-key-{i:04d}").json() for i in range(3)]
    with env.db.sessions.begin() as db:
        for i, data in enumerate(orders):
            order = db.get(Order, data["id"])
            order.created_at = datetime(2026, 10, 21, 1, tzinfo=timezone.utc)
            order.status = "completed" if i < 2 else "cancelled"
            # UTC Oct23 05:59 = Mexico City Oct22 23:59, all belong to Oct22.
            setattr(order, "completed_at" if i < 2 else "cancelled_at", datetime(2026, 10, 23, 5, 59, tzinfo=timezone.utc))
    response = env.client.get("/api/v1/businesses/shop/orders/history?date=2026-10-22&limit=1", headers={"x-user": "operator"})
    assert response.status_code == 200, response.text
    result = response.json()
    assert len(result["data"]) == 1 and result["pagination"]["total"] == 3
    assert result["summary"] == {"completed": 2, "cancelled": 1, "totalSold": 51.0}
    assert all("pickupCode" not in row for row in result["data"])
    empty = env.client.get("/api/v1/businesses/shop/stats?from=2026-10-23&to=2026-10-23", headers={"x-user": "operator"})
    assert empty.json() == {"completed": 0, "cancelled": 0, "totalSold": 0}


def test_media_real_image_is_reencoded_and_mime_spoof_rejected(operations_env):
    env = operations_env
    buffer = io.BytesIO()
    Image.new("RGB", (4, 4), "red").save(buffer, format="PNG")
    response = env.client.post("/api/v1/media", headers={"x-user": "operator"}, data={"purpose": "product"},
                               files={"file": ("../../evil.png", buffer.getvalue(), "image/png")})
    assert response.status_code == 201, response.text
    filename = response.json()["url"].rsplit("/", 1)[1]
    assert "/" not in filename and filename.endswith(".webp")
    with Image.open(env.app.state.settings.media_dir / filename) as image:
        assert image.format == "WEBP"
    spoof = env.client.post("/api/v1/media", headers={"x-user": "operator"}, data={"purpose": "product"},
                            files={"file": ("looks.png", b"<html>not an image</html>", "image/png")})
    assert spoof.status_code == 422
    assert env.client.post("/api/v1/media", headers={"x-user": "admin"}, data={"purpose": "product"},
                            files={"file": ("photo.png", buffer.getvalue(), "image/png")}).status_code == 403


def test_pickup_attempt_limit_survives_failed_transaction(operations_env):
    env = operations_env
    order = buy(env).json()
    for action in ("accept", "start", "ready"):
        order = act(env, order, action).json()
    for _ in range(10):
        assert act(env, order, "complete", method="manual", code="wrong").status_code == 422
    assert act(env, order, "complete", method="manual", code="wrong").status_code == 429
    with env.db.sessions() as db:
        assert db.get(Order, order["id"]).status == "ready"
        assert db.get(Order, order["id"]).version == 4


def test_dtos_match_existing_panel_contract(operations_env):
    from snackup.common import contract
    from jsonschema import Draft202012Validator, FormatChecker
    env = operations_env
    order = buy(env).json()
    spec = contract()
    for schema_name, path in (("Business", "/businesses/shop"), ("Product", "/products/meal"),
                              ("Order", f"/orders/{order['id']}"), ("OrderPage", "/businesses/shop/orders/active")):
        response = env.client.get("/api/v1" + path, headers={"x-user": "operator"})
        assert response.status_code == 200
        schema = {"$ref": "#/components/schemas/" + schema_name, "components": spec["components"]}
        Draft202012Validator(schema, format_checker=FormatChecker()).validate(response.json())
