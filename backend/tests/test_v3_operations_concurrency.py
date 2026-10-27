"""V3 transaction outcomes, exercised with PostgreSQL row/uniqueness locks."""
from concurrent.futures import ThreadPoolExecutor
from threading import Event, Lock
import time
from uuid import uuid4

import pytest
import jwt
from fastapi.testclient import TestClient
from sqlalchemy import event, func, select, text

from snackup.db import OutboxEvent, utcnow
from snackup.identity_models import RefreshSession, User
from snackup.operation_models import Business, IdempotencyRecord, Order, OrderTransition, Product
from test_operations_concurrency import concurrent, require_postgres
from test_v3_operations import purchase

pytestmark = [pytest.mark.v3, pytest.mark.postgres]


def command(headers, *, key=None, quantity=1, business='business-1', product='product-1', expected_total=35.5):
    return ('POST', '/api/v1/orders', {
        'headers': {**headers, 'Idempotency-Key': key or str(uuid4())},
        'json': {'businessId': business, 'items': [{'productId': product, 'quantity': quantity}],
                 'expectedTotal': expected_total},
    })


def test_concurrent_equivalent_uuid_retries_reserve_and_number_once(app, client, tokens):
    require_postgres(app)
    key = str(uuid4())
    first, retry = concurrent(app,
        command(tokens['student'], key=key, quantity=2, expected_total=71),
        command(tokens['student'], key=key.replace('-', '').upper(), quantity=2, expected_total=71.00))
    assert first.status_code == retry.status_code == 201, (first.text, retry.text)
    assert first.json() == retry.json()
    with app.state.db.sessions() as db:
        assert db.get(Product, 'product-1').stock == 8
        assert db.get(Business, 'business-1').next_order_number == 2
        for model in (Order, IdempotencyRecord, OrderTransition):
            assert db.scalar(select(func.count()).select_from(model)) == 1
        assert db.scalar(select(func.count()).select_from(OutboxEvent)) == 4


def test_concurrent_cancellations_without_expected_version_restore_once(app, client, tokens):
    require_postgres(app)
    created = purchase(client, tokens, items=[{'productId': 'product-1', 'quantity': 3}], expectedTotal=106.5)
    assert created.status_code == 201, created.text
    request = ('POST', '/api/v1/orders/' + created.json()['id'] + '/cancel', {
        'headers': tokens['operator'], 'json': {'reason': 'cannot_prepare'},
    })
    results = concurrent(app, request, request)
    assert sorted(row.status_code for row in results) == [200, 400]
    with app.state.db.sessions() as db:
        assert db.get(Product, 'product-1').stock == 10
        order = db.get(Order, created.json()['id'])
        assert order.stock_restored and order.status == 'cancelled' and order.version == 2
        assert db.scalar(select(func.count()).select_from(OrderTransition)) == 2


def test_manual_pause_racing_stock_return_always_preserves_pause(app, client, tokens):
    require_postgres(app)
    created = purchase(client, tokens, items=[{'productId': 'product-1', 'quantity': 10}], expectedTotal=355)
    assert created.status_code == 201, created.text
    paused, returned = concurrent(app,
        ('PATCH', '/api/v1/products/product-1/availability', {
            'headers': tokens['operator'], 'json': {'isAvailable': False}}),
        ('POST', '/api/v1/orders/' + created.json()['id'] + '/cancel', {
            'headers': tokens['student'], 'json': {'reason': 'user_other', 'notes': 'No puedo recoger'}}))
    assert paused.status_code == returned.status_code == 200, (paused.text, returned.text)
    with app.state.db.sessions() as db:
        product = db.get(Product, 'product-1')
        assert product.stock == 10 and not product.manual_available and not product.is_available
        assert product.version == 4


def test_catalog_pause_and_cancellation_use_one_business_product_lock_order(app, client, tokens):
    require_postgres(app)
    created = purchase(client, tokens, items=[{'productId': 'product-1', 'quantity': 10}], expectedTotal=355)
    assert created.status_code == 201, created.text
    catalog_holds_business, release_catalog, cancellation_started = Event(), Event(), Event()
    cancellation_pid = []

    def interleave(connection, cursor, statement, parameters, context, executemany):
        sql = statement.lower().replace("for no key update", "for update")
        if 'from products' in sql and 'products.id =' in sql and 'for update' in sql:
            # The catalog owns Business and has not yet locked Product.
            catalog_holds_business.set()
            assert release_catalog.wait(10), 'Catalog interleaving was not released'
        elif 'from orders' in sql and 'for update' in sql:
            cancellation_pid.append(connection.connection.driver_connection.info.backend_pid)
            cancellation_started.set()

    def send(method, path, body, identity):
        worker = TestClient(app, base_url=app.state.settings.public_origin)
        try:
            return worker.request(method, path, json=body, headers=tokens[identity])
        finally:
            worker.close()

    event.listen(app.state.db.engine, 'before_cursor_execute', interleave)
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            paused = pool.submit(send, 'PATCH', '/api/v1/products/product-1/availability',
                                 {'isAvailable': False}, 'operator')
            try:
                assert catalog_holds_business.wait(10)
                cancelled = pool.submit(send, 'POST', '/api/v1/orders/' + created.json()['id'] + '/cancel',
                                        {'reason': 'user_other', 'notes': 'No puedo recoger'}, 'student')
                assert cancellation_started.wait(10)
                # Observe the actual database wait, not a scheduler delay. The
                # cancellation must wait for Business before retaining Product.
                deadline = time.monotonic() + 10
                with app.state.db.engine.connect().execution_options(isolation_level='AUTOCOMMIT') as monitor:
                    while time.monotonic() < deadline:
                        waiting = monitor.scalar(text('SELECT wait_event_type FROM pg_stat_activity WHERE pid=:pid'),
                                                 {'pid': cancellation_pid[0]})
                        if waiting == 'Lock':
                            break
                        release_catalog.wait(0.01)
                    else:
                        pytest.fail('Cancellation never reached its conflicting database lock')
            finally:
                release_catalog.set()
            responses = [paused.result(timeout=15), cancelled.result(timeout=15)]
    finally:
        release_catalog.set()
        event.remove(app.state.db.engine, 'before_cursor_execute', interleave)
    assert [response.status_code for response in responses] == [200, 200], [response.text for response in responses]
    with app.state.db.sessions() as db:
        product = db.get(Product, 'product-1')
        assert product.stock == 10 and not product.manual_available and not product.is_available
        assert product.version == 4
        assert db.get(Order, created.json()['id']).status == 'cancelled'


def test_price_edit_racing_checkout_rejects_unconfirmed_price_without_partial_reservation(app, client, tokens):
    require_postgres(app)
    changed, bought = concurrent(app,
        ('PATCH', '/api/v1/products/product-1', {
            'headers': tokens['operator'], 'json': {'name': 'Precio nuevo', 'price': 99}}),
        command(tokens['student']))
    assert changed.status_code == 200, changed.text
    assert bought.status_code in (201, 409), bought.text
    success = bought.status_code == 201
    if success:
        assert bought.json()['total'] == 35.5 and bought.json()['items'][0]['name'] == 'Torta'
    else:
        assert bought.json()['error']['code'] == 'PRICE_CHANGED'
        assert bought.json()['error']['details']['currentTotal'] == 99
    with app.state.db.sessions() as db:
        product = db.get(Product, 'product-1')
        assert product.price == 99 and product.stock == (9 if success else 10)
        assert db.get(Business, 'business-1').next_order_number == (2 if success else 1)
        for model in (Order, IdempotencyRecord):
            assert db.scalar(select(func.count()).select_from(model)) == int(success)


def test_close_racing_checkout_serializes_at_business(app, client, tokens):
    require_postgres(app)
    closed, bought = concurrent(app,
        ('PATCH', '/api/v1/businesses/business-1/status', {
            'headers': tokens['operator'], 'json': {'isOpen': False}}),
        command(tokens['student']))
    assert closed.status_code == 200, closed.text
    assert bought.status_code in (201, 409), bought.text
    if bought.status_code == 409:
        assert bought.json()['error']['code'] == 'BUSINESS_CLOSED'
    with app.state.db.sessions() as db:
        assert not db.get(Business, 'business-1').is_open
        assert db.get(Product, 'product-1').stock == (9 if bought.status_code == 201 else 10)


def test_cross_business_concurrent_code_collision_retries_only_the_failed_insert(app, client, tokens, monkeypatch):
    require_postgres(app)
    from snackup import operations
    created = client.post('/api/v1/businesses/business-2/products', headers=tokens['other-operator'],
                          json={'name': 'Agua', 'category': 'Bebida', 'price': 10, 'stock': 10})
    assert created.status_code == 201, created.text
    codes = iter(['ABC123', 'ABC123', 'XYZ456'])
    generator_lock = Lock()
    def generate():
        with generator_lock:
            return next(codes)
    monkeypatch.setattr(operations, 'generate_pickup_code', generate)
    first, second = concurrent(app, command(tokens['student']),
        command(tokens['other-student'], business='business-2', product=created.json()['id'], expected_total=10))
    assert first.status_code == second.status_code == 201, (first.text, second.text)
    assert {first.json()['pickupCode'], second.json()['pickupCode']} == {'ABC123', 'XYZ456'}
    assert first.json()['orderNumber'] == second.json()['orderNumber'] == 1
    with app.state.db.sessions() as db:
        assert db.get(Product, 'product-1').stock == 9
        assert db.get(Product, created.json()['id']).stock == 9
        assert db.get(Business, 'business-1').next_order_number == db.get(Business, 'business-2').next_order_number == 2
        for model in (Order, IdempotencyRecord, OrderTransition):
            assert db.scalar(select(func.count()).select_from(model)) == 2


@pytest.mark.parametrize('operation', ['create', 'accept', 'product_update', 'business_status'])
def test_waiting_mutation_observes_committed_session_family_revocation(app, client, tokens, operation):
    require_postgres(app)
    if operation == 'create':
        identity, locked_model, locked_id, table = 'student', User, 'student', 'users'
        request = command(tokens[identity])
    elif operation == 'accept':
        created = purchase(client, tokens)
        assert created.status_code == 201, created.text
        identity, locked_model, locked_id, table = 'operator', Order, created.json()['id'], 'orders'
        request = ('POST', '/api/v1/orders/' + locked_id + '/accept', {'headers': tokens[identity], 'json': {}})
    elif operation == 'product_update':
        identity, locked_model, locked_id, table = 'operator', Product, 'product-1', 'products'
        request = ('PATCH', '/api/v1/products/product-1', {
            'headers': tokens[identity], 'json': {'name': 'Cambio no autorizado', 'stock': 8}})
    else:
        identity, locked_model, locked_id, table = 'operator', Business, 'business-1', 'businesses'
        request = ('PATCH', '/api/v1/businesses/business-1/status', {
            'headers': tokens[identity], 'json': {'isOpen': False}})
    # Extract only the fixture session identifier, never log access credentials.
    session_id = jwt.decode(tokens[identity]['Authorization'].split()[1], options={'verify_signature': False})['sid']
    waiting = Event()

    def observe_lock(connection, cursor, statement, parameters, context, executemany):
        sql = statement.lower().replace("for no key update", "for update")
        if f'from {table}' in sql and 'for update' in sql:
            waiting.set()

    def send():
        worker = TestClient(app, base_url=app.state.settings.public_origin)
        try:
            method, path, kwargs = request
            return worker.request(method, path, **kwargs)
        finally:
            worker.close()

    with app.state.db.sessions() as blocker:
        blocker.begin()
        blocker.scalar(select(locked_model).where(locked_model.id == locked_id).with_for_update())
        event.listen(app.state.db.engine, 'before_cursor_execute', observe_lock)
        try:
            with ThreadPoolExecutor(max_workers=1) as pool:
                future = pool.submit(send)
                try:
                    assert waiting.wait(10), 'Mutation did not reach its serialization lock'
                    blocker.get(RefreshSession, session_id).revoked_at = utcnow()
                    blocker.commit()
                finally:
                    blocker.rollback()
                response = future.result(timeout=15)
        finally:
            event.remove(app.state.db.engine, 'before_cursor_execute', observe_lock)
    assert response.status_code == 401, response.text
    assert response.json()['error']['code'] == 'UNAUTHENTICATED'
    with app.state.db.sessions() as db:
        expected_orders = int(operation == 'accept')
        assert db.scalar(select(func.count()).select_from(Order)) == expected_orders
        assert db.scalar(select(func.count()).select_from(OrderTransition)) == expected_orders
        assert db.get(Product, 'product-1').stock == (9 if expected_orders else 10)
        assert db.get(Product, 'product-1').name == 'Torta'
        assert db.get(Business, 'business-1').is_open
        assert db.scalar(select(func.count()).select_from(OutboxEvent)) == (4 if expected_orders else 0)
        if operation == 'accept':
            assert db.get(Order, locked_id).status == 'pending'
