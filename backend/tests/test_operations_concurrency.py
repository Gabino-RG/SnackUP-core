"""Database concurrency guarantees, exercised only on real PostgreSQL.

SQLite passing tests cannot prove row locking. CI supplies a disposable database
and the shared fixture creates a fresh schema for each case.
"""
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier, Event
from uuid import uuid4

from fastapi.testclient import TestClient
import pytest
from sqlalchemy import event, func, select

from snackup.db import OutboxEvent
from snackup.identity_models import AcademicRecord, User
from snackup.operation_models import Business, IdempotencyRecord, Order, OrderTransition, Product

pytestmark = pytest.mark.postgres


def require_postgres(app):
    if app.state.db.engine.dialect.name != "postgresql":
        pytest.skip("Real PostgreSQL is required to verify transaction locks")


def concurrent(app, *requests):
    barrier = Barrier(len(requests))

    def send(args):
        method, path, kwargs = args
        # Reuse the running app without entering lifespan in each worker.
        c = TestClient(app, base_url=app.state.settings.public_origin)
        try:
            barrier.wait(timeout=10)
            return c.request(method, path, **kwargs)
        finally:
            c.close()

    with ThreadPoolExecutor(max_workers=len(requests)) as pool:
        futures = [pool.submit(send, args) for args in requests]
        return [future.result(timeout=20) for future in futures]


def purchase(headers, key=None, quantity=1):
    return ("POST", "/api/legacy/v1/student/orders", {
        "headers": {**headers, "Idempotency-Key": key or uuid4().hex},
        "json": {"businessId": "business-1", "items": [{"productId": "product-1", "quantity": quantity}]},
    })


def test_simultaneous_same_idempotency_key_creates_one_order(app, client, tokens):
    require_postgres(app)
    request = purchase(tokens["student"], key=uuid4().hex, quantity=2)
    a, b = concurrent(app, request, request)
    assert a.status_code == b.status_code == 201, (a.text, b.text)
    assert a.json() == b.json()
    with app.state.db.sessions() as db:
        assert db.get(Product, "product-1").stock == 8
        assert db.get(Business, "business-1").next_order_number == 2
        for model in (Order, IdempotencyRecord, OrderTransition):
            assert db.scalar(select(func.count()).select_from(model)) == 1
        assert db.scalar(select(func.count()).select_from(OutboxEvent)) == 4


def test_simultaneous_cancellation_returns_inventory_once(app, client, tokens):
    require_postgres(app)
    _, path, options = purchase(tokens["student"], quantity=3)
    created = client.post(path, **options)
    assert created.status_code == 201, created.text
    order = created.json()
    request = ("POST", f"/api/legacy/v1/orders/{order['id']}/cancel", {
        "headers": tokens["operator"], "json": {"expectedVersion": 1, "reason": "cannot_prepare"},
    })
    responses = concurrent(app, request, request)
    assert sorted(response.status_code for response in responses) == [200, 409]
    with app.state.db.sessions() as db:
        assert db.get(Product, "product-1").stock == 10
        assert db.get(Order, order["id"]).version == 2
        assert db.get(Order, order["id"]).stock_restored
        assert db.scalar(select(func.count()).select_from(OrderTransition)) == 2


def test_price_edit_racing_purchase_cannot_overwrite_stock_or_old_snapshot(app, client, tokens):
    require_postgres(app)
    edit = ("PATCH", "/api/legacy/v1/products/product-1", {
        "headers": tokens["operator"],
        "json": {"name": "Nueva torta", "description": "", "category": "Comida", "price": 99,
                 "imageUrl": None, "isAvailable": True, "isFeatured": False, "expectedVersion": 1},
    })
    changed, bought = concurrent(app, edit, purchase(tokens["student"], quantity=2))
    assert bought.status_code == 201, bought.text
    assert changed.status_code in (200, 409), changed.text
    order = bought.json()
    if changed.status_code == 200:
        assert order["total"] == 198.0 and order["items"][0]["name"] == "Nueva torta"
    else:
        assert order["total"] == 71.0 and order["items"][0]["name"] == "Torta"
    with app.state.db.sessions() as db:
        assert db.get(Product, "product-1").stock == 8
        assert db.get(Product, "product-1").version == (3 if changed.status_code == 200 else 2)


def test_business_disable_and_purchase_have_a_consistent_serial_order(app, client, tokens):
    require_postgres(app)
    disable = ("PATCH", "/api/legacy/v1/admin/businesses/business-1", {
        "headers": tokens["admin"],
        "json": {"name": "Cafetería Uno", "category": "", "description": "", "isActive": False,
                 "cafeteriaId": "cafeteria", "expectedVersion": 1},
    })
    disabled, bought = concurrent(app, disable, purchase(tokens["student"]))
    assert (disabled.status_code, bought.status_code) in ((200, 404), (409, 201)), (disabled.text, bought.text)
    with app.state.db.sessions() as db:
        business = db.get(Business, "business-1")
        total_orders = db.scalar(select(func.count()).select_from(Order))
        if disabled.status_code == 200:
            assert not business.is_active and not business.is_open and total_orders == 0
            assert db.get(Product, "product-1").stock == 10
        else:
            assert business.is_active and total_orders == 1
            assert db.get(Product, "product-1").stock == 9


def test_waiting_student_purchase_rechecks_committed_roster_revocation(app, client, tokens):
    require_postgres(app)
    waiting_on_user = Event()

    def observe_lock(connection, cursor, statement, parameters, context, executemany):
        sql = statement.lower().replace("for no key update", "for update")
        if "from users" in sql and "for update" in sql:
            waiting_on_user.set()

    observing = False
    try:
        with app.state.db.sessions() as blocker:
            blocker.begin()
            blocker.scalar(select(User).where(User.id == "student").with_for_update())
            event.listen(app.state.db.engine, "before_cursor_execute", observe_lock)
            observing = True
            with ThreadPoolExecutor(max_workers=1, thread_name_prefix="revocation-buy") as pool:
                def buy():
                    c = TestClient(app, base_url=app.state.settings.public_origin)
                    try:
                        _, path, options = purchase(tokens["student"])
                        return c.post(path, **options)
                    finally:
                        c.close()

                future = pool.submit(buy)
                try:
                    assert waiting_on_user.wait(10), "Purchase did not reach its serialization lock"
                    # Same lock order as an authorized institutional import: User then roster.
                    record = blocker.scalar(select(AcademicRecord).where(
                        AcademicRecord.email == "student@students.example.edu").with_for_update())
                    record.is_active = False
                    blocker.commit()
                finally:
                    blocker.rollback()
                response = future.result(timeout=15)
        assert response.status_code == 403, response.text
        assert response.json()["error"]["code"] == "ACCESS_REVOKED"
        with app.state.db.sessions() as db:
            assert db.scalar(select(func.count()).select_from(Order)) == 0
            assert db.get(Product, "product-1").stock == 10
    finally:
        if observing:
            event.remove(app.state.db.engine, "before_cursor_execute", observe_lock)
