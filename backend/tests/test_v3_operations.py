"""Canonical V3 acceptance cases against the real transactional application."""
from decimal import Decimal
import re
from uuid import uuid4

import pytest
from sqlalchemy import func, select

from snackup.admin_models import Review
from snackup.db import OutboxEvent
from snackup.operation_models import Business, IdempotencyRecord, Order, OrderItem, OrderTransition, Product
from snackup.review_models import ProductReview

pytestmark = pytest.mark.v3
PASSWORD = 'Test-Only-Password-392!'


@pytest.fixture
def headers(client):
    result = {}
    for identity in ('student', 'other-student', 'operator', 'other-operator', 'admin'):
        domain = 'students.example.edu' if 'student' in identity else 'staff.example.edu'
        response = client.post('/api/legacy/v1/auth/login',
                               json={'email': identity + '@' + domain, 'password': PASSWORD},
                               headers={'Origin': 'http://testserver'})
        assert response.status_code == 200, response.text
        result[identity] = {'Authorization': 'Bearer ' + response.json()['tokens']['accessToken'],
                            'Origin': 'http://testserver'}
    return result


def purchase(client, headers, *, identity='student', key=None, **changes):
    payload = {'businessId': 'business-1', 'items': [{'productId': 'product-1', 'quantity': 1}],
               'paymentMethod': 'Efectivo', 'expectedTotal': 35.50, **changes}
    return client.post('/api/v1/orders', json=payload,
                       headers={**headers[identity], 'Idempotency-Key': key or str(uuid4())})


def action(client, headers, order, operation, *, identity='operator', **changes):
    return client.post(f"/api/v1/orders/{order['id']}/{operation}",
                       headers=headers[identity], json=changes)


def test_price_conflict_is_atomic_and_key_can_be_used_after_confirmation(app, client, headers):
    key = str(uuid4())
    rejected = purchase(client, headers, key=key, expectedTotal=0.01)
    assert rejected.status_code == 409, rejected.text
    assert rejected.json()['error'] == {
        'code': 'PRICE_CHANGED', 'message': 'El precio cambió. Revisa el total antes de confirmar.',
        'details': {'currentTotal': 35.5},
    }
    with app.state.db.sessions() as db:
        assert db.scalar(select(func.count()).select_from(Order)) == 0
        assert db.scalar(select(func.count()).select_from(IdempotencyRecord)) == 0
        assert db.scalar(select(func.count()).select_from(OutboxEvent)) == 0
        assert db.get(Product, 'product-1').stock == 10
        assert db.get(Business, 'business-1').next_order_number == 1
    created = purchase(client, headers, key=key)
    assert created.status_code == 201, created.text
    assert re.fullmatch('[A-Z0-9]{6}', created.json()['pickupCode'])
    assert created.json()['customerNumeroDeControl'] == 'ID-student'
    assert created.json()['subtotal'] == created.json()['total'] == 35.5


def test_imported_opaque_ids_longer_than_event_topic_limit_work_end_to_end(app, client, headers):
    business_id = 'imported-business-' + 'b' * 300
    product_id = 'imported-product-' + 'p' * 300
    with app.state.db.sessions.begin() as db:
        db.add(Business(id=business_id, name='Local importado', cafeteria_id='cafeteria',
                        cafeteria_name='Cafetería', is_open=True))
        db.flush()
        db.add(Product(id=product_id, business_id=business_id, name='Producto importado',
                       category='Comida', price=Decimal('35.50'), stock=3))
    catalog = client.get('/api/v1/businesses/' + business_id + '/products', headers=headers['student'])
    assert catalog.status_code == 200, catalog.text
    assert catalog.json()['data'][0]['id'] == product_id
    detail = client.get('/api/v1/products/' + product_id, headers=headers['student'])
    assert detail.status_code == 200 and detail.json()['businessId'] == business_id
    created = purchase(client, headers, businessId=business_id, items=[{'productId': product_id, 'quantity': 1}])
    assert created.status_code == 201, created.text
    assert created.json()['businessId'] == business_id and created.json()['items'][0]['productId'] == product_id
    with app.state.db.sessions() as db:
        assert db.get(Product, product_id).stock == 2
        topics = set(db.scalars(select(OutboxEvent.topic)))
        assert f'business:{business_id}:orders' in topics
        assert f'business:{business_id}:products' in topics


@pytest.mark.parametrize('contract', ['v3', 'legacy'])
def test_order_count_advances_business_version_once_and_publishes_invalidation(app, client, headers, contract):
    before = client.get('/api/v1/businesses/business-1', headers=headers['student']).json()
    key = str(uuid4())
    path = '/api/v1/orders' if contract == 'v3' else '/api/legacy/v1/student/orders'
    body = {'businessId': 'business-1', 'items': [{'productId': 'product-1', 'quantity': 1}]}
    if contract == 'v3':
        body.update(expectedTotal=35.5, paymentMethod='Efectivo')
    request_headers = {**headers['student'], 'Idempotency-Key': key}
    created = client.post(path, json=body, headers=request_headers)
    assert created.status_code == 201, created.text
    retry = client.post(path, json=body, headers=request_headers)
    assert retry.status_code == 201 and retry.json() == created.json()
    after = client.get('/api/v1/businesses/business-1', headers=headers['student']).json()
    assert after['totalOrders'] == before['totalOrders'] + 1
    with app.state.db.sessions() as db:
        counted = db.scalar(select(func.count()).select_from(Order).where(Order.business_id == 'business-1'))
    listed = client.get('/api/v1/businesses', headers=headers['student']).json()['data']
    assert after['totalOrders'] == counted == next(b['totalOrders'] for b in listed if b['id'] == 'business-1')
    assert after['version'] == before['version'] + 1
    assert after['updatedAt'] > before['updatedAt']
    stale = client.patch('/api/v1/businesses/business-1/status', headers=headers['operator'],
                         json={'isOpen': False, 'expectedVersion': before['version']})
    assert stale.status_code == 409 and stale.json()['error']['code'] == 'VERSION_CONFLICT'
    with app.state.db.sessions() as db:
        events = db.scalars(select(OutboxEvent).where(OutboxEvent.event_type == 'business.updated')).all()
        assert len(events) == 1
        assert events[0].topic == 'business:business-1'
        assert events[0].data == {'id': 'business-1', 'version': after['version'], 'updatedAt': after['updatedAt']}


def test_legacy_catalog_and_inventory_changes_invalidate_v3_menu(app, client, headers):
    draft = {'name': 'Producto desde Cocina anterior', 'description': '', 'category': 'Comida',
             'price': 10, 'stock': 2, 'imageUrl': None, 'isAvailable': True, 'isFeatured': False}
    created = client.post('/api/legacy/v1/businesses/business-1/products',
                          headers=headers['operator'], json=draft)
    assert created.status_code == 201, created.text
    product_id = created.json()['id']
    current = client.get('/api/v1/products/' + product_id, headers=headers['student']).json()
    assert current['price'] == 10 and current['version'] == 1
    updated = client.patch('/api/legacy/v1/products/' + product_id, headers=headers['operator'],
                           json={**draft, 'price': 12, 'expectedVersion': 1})
    assert updated.status_code == 200, updated.text
    current = client.get('/api/v1/products/' + product_id, headers=headers['student']).json()
    assert current['price'] == 12 and current['version'] == 2
    bought = client.post('/api/legacy/v1/student/orders',
                         headers={**headers['student'], 'Idempotency-Key': str(uuid4())},
                         json={'businessId': 'business-1', 'items': [{'productId': product_id, 'quantity': 2}]})
    assert bought.status_code == 201, bought.text
    current = client.get('/api/v1/products/' + product_id, headers=headers['student']).json()
    assert current['stock'] == 0 and not current['isAvailable'] and current['version'] == 3
    cancelled = client.post('/api/legacy/v1/orders/' + bought.json()['id'] + '/cancel',
                            headers=headers['operator'], json={'reason': 'cannot_prepare', 'expectedVersion': 1})
    assert cancelled.status_code == 200, cancelled.text
    current = client.get('/api/v1/products/' + product_id, headers=headers['student']).json()
    assert current['stock'] == 2 and current['isAvailable'] and current['version'] == 4
    deleted = client.request('DELETE', '/api/legacy/v1/products/' + product_id,
                             headers=headers['operator'], json={'expectedVersion': 4})
    assert deleted.status_code == 204, deleted.text
    assert client.get('/api/v1/products/' + product_id, headers=headers['student']).status_code == 404
    menu = client.get('/api/v1/businesses/business-1/products', headers=headers['student']).json()
    assert product_id not in {row['id'] for row in menu['data']}
    with app.state.db.sessions() as db:
        events = db.scalars(select(OutboxEvent).where(OutboxEvent.event_type == 'product.updated')
                            .order_by(OutboxEvent.id)).all()
        assert len(events) == 5
        assert all(event.topic == 'business:business-1:products' and event.data['id'] == product_id
                   for event in events)
        assert [event.data['version'] for event in events] == [1, 2, 3, 4, 5]
        assert [event.data['stock'] for event in events] == [2, 2, 0, 2, 2]
        assert [event.data['isAvailable'] for event in events] == [True, True, False, True, False]
        assert all(event.data['deletedAt'] is None for event in events[:-1])
        assert events[-1].data['deletedAt'] is not None


def test_canonical_idempotency_and_payment_method_without_collecting_money(app, client, headers):
    key = str(uuid4())
    first = purchase(client, headers, key=key, paymentMethod='Transferencia')
    assert first.status_code == 201, first.text
    # UUID textual normalization and equivalent monetary JSON keep one intent.
    retry = purchase(client, headers, key=key.replace('-', '').upper(), expectedTotal=35.500,
                     paymentMethod='Transferencia')
    assert retry.status_code == 201 and retry.json() == first.json()
    assert first.json()['paymentMethod'] == 'Transferencia'
    assert first.json()['paymentStatus'] == 'unverified'
    conflict = purchase(client, headers, key=key)
    assert conflict.status_code == 409 and conflict.json()['error']['code'] == 'IDEMPOTENCY_CONFLICT'
    with app.state.db.sessions() as db:
        assert db.scalar(select(func.count()).select_from(Order)) == 1
        assert db.get(Product, 'product-1').stock == 9
    invalid = purchase(client, headers, key='this-is-not-a-valid-uuid-key-00000')
    assert invalid.status_code == 422 and invalid.json()['error']['code'] == 'INVALID_IDEMPOTENCY_KEY'


@pytest.mark.parametrize('changes,status,code', [
    ({'items': []}, 400, 'INVALID_ITEMS'),
    ({'items': [{'productId': 'product-1', 'quantity': 0}]}, 400, 'INVALID_ITEMS'),
    ({'items': [{'productId': 'product-1', 'quantity': True}]}, 400, 'INVALID_ITEMS'),
    ({'items': [{'productId': 'missing-product', 'quantity': 1}]}, 422, 'PRODUCT_NOT_IN_BUSINESS'),
    ({'items': [{'productId': 'product-1', 'quantity': 11}], 'expectedTotal': 390.5}, 422, 'PRODUCT_UNAVAILABLE'),
    ({'scheduledPickupTime': '2030-01-01T00:00:00Z'}, 422, 'INVALID_SCHEDULE'),
    ({'expectedTotal': '35.50'}, 422, 'INVALID_INPUT'),
    ({'expectedTotal': 35.501}, 422, 'INVALID_INPUT'),
    ({'total': 0.01}, 422, 'INVALID_INPUT'),
])
def test_invalid_order_inputs_do_not_write(app, client, headers, changes, status, code):
    response = purchase(client, headers, **changes)
    assert response.status_code == status, response.text
    assert response.json()['error']['code'] == code
    with app.state.db.sessions() as db:
        assert db.scalar(select(func.count()).select_from(Order)) == 0
        assert db.get(Product, 'product-1').stock == 10


def test_collision_retry_savepoint_preserves_consecutive_numbers_and_inventory(app, client, headers, monkeypatch):
    from snackup import operations
    codes = iter(['ABC123', 'ABC123', 'XYZ456'])
    monkeypatch.setattr(operations, 'generate_pickup_code', lambda: next(codes))
    first = purchase(client, headers)
    second = purchase(client, headers, identity='other-student')
    assert first.status_code == second.status_code == 201, (first.text, second.text)
    assert first.json()['pickupCode'] == 'ABC123'
    assert second.json()['pickupCode'] == 'XYZ456'
    assert [first.json()['orderNumber'], second.json()['orderNumber']] == [1, 2]
    with app.state.db.sessions() as db:
        assert db.get(Product, 'product-1').stock == 8
        assert db.get(Business, 'business-1').next_order_number == 3
        for model in (Order, OrderItem, IdempotencyRecord, OrderTransition):
            assert db.scalar(select(func.count()).select_from(model)) == 2


def test_code_collision_exhaustion_rolls_back_outer_transaction(app, client, headers, monkeypatch):
    from snackup import operations
    monkeypatch.setattr(operations, 'generate_pickup_code', lambda: 'ABC123')
    assert purchase(client, headers).status_code == 201
    rejected = purchase(client, headers, identity='other-student')
    assert rejected.status_code == 503, rejected.text
    with app.state.db.sessions() as db:
        assert db.scalar(select(func.count()).select_from(Order)) == 1
        assert db.scalar(select(func.count()).select_from(IdempotencyRecord)) == 1
        assert db.get(Product, 'product-1').stock == 9
        assert db.get(Business, 'business-1').next_order_number == 2


def test_manual_pause_survives_cancellation_and_stock_edit(app, client, headers):
    order = purchase(client, headers, items=[{'productId': 'product-1', 'quantity': 10}], expectedTotal=355).json()
    paused = client.patch('/api/v1/products/product-1/availability', headers=headers['operator'],
                          json={'isAvailable': False, 'expectedVersion': 2})
    assert paused.status_code == 200, paused.text
    cancelled = action(client, headers, order, 'cancel', identity='student', reason='user_other', notes='No puedo recoger')
    assert cancelled.status_code == 200, cancelled.text
    assert cancelled.json()['cancelledBy'] == 'ALUMNO'
    assert cancelled.json()['cancelReason'] == 'user_other'
    current = client.get('/api/v1/products/product-1', headers=headers['student']).json()
    assert current['stock'] == 10 and current['isAvailable'] is False
    edited = client.patch('/api/v1/products/product-1', headers=headers['operator'], json={'stock': 12})
    assert edited.status_code == 200 and edited.json()['isAvailable'] is False
    resumed = client.patch('/api/v1/products/product-1/availability', headers=headers['operator'], json={'isAvailable': True})
    assert resumed.status_code == 200 and resumed.json()['isAvailable'] is True
    with app.state.db.sessions() as db:
        events = db.scalars(select(OutboxEvent).where(OutboxEvent.event_type == 'product.updated')).all()
        assert len(events) == 5
        assert all('pickupCode' not in event.data and 'customerNumeroDeControl' not in event.data for event in events)


def test_automatic_exhaustion_recovers_without_overriding_manual_intent(client, headers):
    order = purchase(client, headers, items=[{'productId': 'product-1', 'quantity': 10}], expectedTotal=355).json()
    product = client.get('/api/v1/products/product-1', headers=headers['student']).json()
    assert product['stock'] == 0 and product['isAvailable'] is False
    response = action(client, headers, order, 'cancel', reason='cannot_prepare')
    assert response.status_code == 200
    product = client.get('/api/v1/products/product-1', headers=headers['student']).json()
    assert product['stock'] == 10 and product['isAvailable'] is True


def test_optional_version_strict_states_privacy_and_terminal_reconnect_delta(app, client, headers):
    created = purchase(client, headers).json()
    assert client.get(f"/api/v1/orders/{created['id']}", headers=headers['other-student']).status_code == 404
    assert client.get(f"/api/v1/orders/{created['id']}", headers=headers['other-operator']).status_code == 404
    assert client.get(f"/api/v1/orders/{created['id']}", headers=headers['admin']).status_code == 403
    invalid = action(client, headers, created, 'ready')
    assert invalid.status_code == 400 and invalid.json()['error']['code'] == 'INVALID_STATUS_TRANSITION'
    accepted = action(client, headers, created, 'accept')
    assert accepted.status_code == 200 and accepted.json()['version'] == 2
    for field in ('pickupCode', 'customerNumeroDeControl', 'userId'):
        assert field not in accepted.json()
    stale = action(client, headers, created, 'start', expectedVersion=1)
    assert stale.status_code == 409 and stale.json()['error']['details']['currentVersion'] == 2
    for invalid_version in (True, None, 0, -1, '2'):
        assert action(client, headers, created, 'start', expectedVersion=invalid_version).status_code == 422
    assert action(client, headers, created, 'start', expectedVersion=2).status_code == 200
    assert action(client, headers, created, 'ready').status_code == 200
    assert action(client, headers, created, 'cancel', reason='cannot_prepare').status_code == 400
    assert action(client, headers, created, 'complete', method='manual', code='wrong').status_code == 422
    completed = action(client, headers, created, 'complete', method='manual', code=created['pickupCode'])
    assert completed.status_code == 200, completed.text
    assert completed.json()['verification']['verifiedBy'] == 'operator'
    assert completed.json()['verification']['verifiedAt']
    assert completed.json()['paymentStatus'] == 'pay_at_pickup'
    assert 'pickupCode' not in completed.json()
    assert client.get('/api/v1/businesses/business-1/orders/active', headers=headers['operator']).json()['data'] == []
    delta = client.get('/api/v1/businesses/business-1/orders/active', headers=headers['operator'],
                       params={'updatedSince': created['createdAt']}).json()
    assert [row['status'] for row in delta['data']] == ['completed']
    assert client.get('/api/v1/users/me/orders/active', headers=headers['student']).json()['data'] == []
    with app.state.db.sessions() as db:
        audit = db.scalars(select(OrderTransition).order_by(OrderTransition.version)).all()
        assert [(row.action, row.actor_role) for row in audit] == [
            ('created', 'ALUMNO'), ('accept', 'COCINA'), ('start', 'COCINA'), ('ready', 'COCINA'), ('complete', 'COCINA')]
        assert all('pickupCode' not in event.data for event in db.scalars(select(OutboxEvent)))


def test_student_cancellation_rejects_unverified_catalog_and_role_forgery(client, headers):
    created = purchase(client, headers).json()
    for payload in ({'reason': 'other', 'notes': 'reason'}, {'reason': 'user_other'},
                    {'reason': 'user_changed_mind', 'notes': 'not yet verified V2'},
                    {'reason': 'user_other', 'notes': 'reason', 'cancelledBy': 'COCINA'}):
        assert action(client, headers, created, 'cancel', identity='student', **payload).status_code == 422
    assert action(client, headers, created, 'accept').status_code == 200
    blocked = action(client, headers, created, 'cancel', identity='student', reason='user_other', notes='reason')
    assert blocked.status_code == 400


def test_catalog_projection_server_aggregates_and_snapshots(app, client, headers):
    created = purchase(client, headers).json()
    with app.state.db.sessions.begin() as db:
        row = db.get(Order, created['id'])
        row.status = 'completed'
        db.add(Review(order_id=row.id, user_id='student', business_id='business-1', rating=4, comment='Review'))
        db.add(ProductReview(order_id=row.id, user_id='student', product_id='product-1', rating=5, comment='Product'))
    business = client.get('/api/v1/businesses/business-1', headers=headers['student']).json()
    assert business['ownerId'] == 'operator'
    assert (business['averageRating'], business['totalRatings'], business['totalOrders']) == (4, 1, 1)
    assert 'nextOrderNumber' not in business
    products = client.get('/api/v1/businesses/business-1/products', headers=headers['student'],
                          params={'fields': 'id,name,averageRating,totalReviews'}).json()
    assert products['data'] == [{'id': 'product-1', 'name': 'Torta', 'averageRating': 5, 'totalReviews': 1}]
    assert client.get('/api/v1/businesses/business-2/products', headers=headers['operator']).status_code == 403
    assert client.get('/api/v1/businesses/business-1/products', headers=headers['student'],
                      params={'fields': 'password_hash'}).status_code == 422
    changed = client.patch('/api/v1/products/product-1', headers=headers['operator'], json={'name': 'Nueva torta', 'price': 42})
    assert changed.status_code == 200, changed.text
    order = client.get(f"/api/v1/orders/{created['id']}", headers=headers['student']).json()
    assert order['items'][0]['name'] == 'Torta' and order['items'][0]['price'] == 35.5
    assert order['isRated'] is True


def test_product_deletion_preserves_order_and_stock_without_relisting(client, headers):
    created = purchase(client, headers).json()
    removed = client.delete('/api/v1/products/product-1', headers=headers['operator'])
    assert removed.status_code == 204, removed.text
    assert client.get('/api/v1/products/product-1', headers=headers['student']).status_code == 404
    cancelled = action(client, headers, created, 'cancel', reason='product_unavailable')
    assert cancelled.status_code == 200
    order = client.get(f"/api/v1/orders/{created['id']}", headers=headers['student']).json()
    assert order['items'][0]['price'] == 35.5
    assert client.get('/api/v1/businesses/business-1/products', headers=headers['student']).json()['data'] == []


def test_stock_zero_can_preserve_intent_and_closed_business_blocks_new_orders(client, headers):
    created = client.post('/api/v1/businesses/business-1/products', headers=headers['operator'],
                          json={'name': 'Agua', 'category': 'Bebida', 'price': 10, 'stock': 0, 'isAvailable': True})
    assert created.status_code == 201, created.text
    assert created.json()['isAvailable'] is False
    replenished = client.patch('/api/v1/products/' + created.json()['id'], headers=headers['operator'], json={'stock': 5})
    assert replenished.json()['isAvailable'] is True
    closed = client.patch('/api/v1/businesses/business-1/status', headers=headers['operator'], json={'isOpen': False})
    assert closed.status_code == 200
    rejected = purchase(client, headers)
    assert rejected.status_code == 409 and rejected.json()['error']['code'] == 'BUSINESS_CLOSED'


def test_legacy_pickup_code_stays_usable_through_canonical_routes(client, headers):
    old = client.post('/api/legacy/v1/student/orders', headers={**headers['student'], 'Idempotency-Key': 'legacy-order-key-0001'},
                      json={'businessId': 'business-1', 'items': [{'productId': 'product-1', 'quantity': 1}]})
    assert old.status_code == 201, old.text
    order = old.json()
    assert re.fullmatch('[0-9]{8}', order['pickupCode'])
    for verb in ('accept', 'start', 'ready'):
        assert action(client, headers, order, verb).status_code == 200
    delivered = action(client, headers, order, 'complete', method='qr', code=order['pickupCode'])
    assert delivered.status_code == 200
    view = client.get(f"/api/v1/orders/{order['id']}", headers=headers['student']).json()
    assert view['pickupCode'] == order['pickupCode'] and view['paymentMethod'] == 'Efectivo'


@pytest.mark.parametrize('method,legacy_method,payment_status', [
    ('Efectivo', 'cash', 'pay_at_pickup'), ('Transferencia', 'Transferencia', 'unverified'),
])
def test_v3_orders_remain_readable_and_deliverable_by_legacy_clients(client, headers, method, legacy_method, payment_status):
    created = purchase(client, headers, paymentMethod=method)
    assert created.status_code == 201, created.text
    order = created.json()
    student = client.get('/api/legacy/v1/student/orders/' + order['id'], headers=headers['student'])
    assert student.status_code == 200, student.text
    assert student.json()['paymentMethod'] == legacy_method
    assert student.json()['paymentStatus'] == payment_status
    assert student.json()['pickupCode'] == order['pickupCode']
    listing = client.get('/api/legacy/v1/student/orders', headers=headers['student'])
    assert listing.status_code == 200 and listing.json()['data'][0]['id'] == order['id']
    for operation in ('accept', 'start', 'ready', 'complete'):
        body = {'expectedVersion': order['version']}
        if operation == 'complete':
            body.update(method='manual', code=created.json()['pickupCode'])
        response = client.post('/api/legacy/v1/orders/' + order['id'] + '/' + operation,
                               headers=headers['operator'], json=body)
        assert response.status_code == 200, response.text
        order = response.json()
        assert 'pickupCode' not in order
        assert order['paymentMethod'] == legacy_method and order['paymentStatus'] == payment_status
    assert order['status'] == 'completed'


def test_two_students_last_unit_remains_atomic(app, client, headers):
    if app.state.db.engine.dialect.name != 'postgresql':
        pytest.skip('PostgreSQL required for real row-lock concurrency')
    from test_operations_concurrency import concurrent
    with app.state.db.sessions.begin() as db:
        db.get(Product, 'product-1').stock = 1
    def command(identity, key):
        return ('POST', '/api/v1/orders', {'headers': {**headers[identity], 'Idempotency-Key': key},
                'json': {'businessId': 'business-1', 'items': [{'productId': 'product-1', 'quantity': 1}],
                         'expectedTotal': 35.50}})
    first, second = concurrent(app, command('student', str(uuid4())), command('other-student', str(uuid4())))
    assert sorted([first.status_code, second.status_code]) == [201, 422], (first.text, second.text)
    with app.state.db.sessions() as db:
        assert db.get(Product, 'product-1').stock == 0
        assert db.scalar(select(func.count()).select_from(Order)) == 1
        assert db.scalar(select(func.sum(Order.total))) == Decimal('35.50')
