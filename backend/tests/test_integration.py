from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from threading import Barrier
from uuid import uuid4
from zoneinfo import ZoneInfo

from fastapi.testclient import TestClient
import pytest
from sqlalchemy import func, select

from snackup.db import OutboxEvent
from snackup.operation_models import Order, OrderItem, Product


def create_order(client, header, key=None, quantity=1):
    return client.post('/api/v1/student/orders', headers={**header, 'Idempotency-Key': key or uuid4().hex},
                       json={'businessId': 'business-1', 'items': [{'productId': 'product-1', 'quantity': quantity}], 'paymentMethod': 'cash'})


def test_student_kitchen_admin_roundtrip(client, app, tokens):
    student, operator, admin = tokens['student'], tokens['operator'], tokens['master']
    profile = client.get('/api/v1/users/me', headers=student)
    assert profile.status_code == 200
    created = create_order(client, student)
    assert created.status_code == 201, created.text
    order = created.json()
    key = order['id']
    pickup = order['pickupCode']
    assert len(pickup) >= 8
    denied = client.get('/api/v1/student/orders/' + key, headers=tokens['other-student'])
    assert denied.status_code in {403, 404}
    kitchen = client.get('/api/v1/businesses/business-1/orders/active', headers=operator)
    assert kitchen.status_code == 200
    assert kitchen.json()['data'][0]['id'] == key
    assert 'pickupCode' not in kitchen.json()['data'][0]
    assert 'customerNumeroDeControl' not in kitchen.json()['data'][0]
    assert client.get('/api/v1/orders/' + key, headers=admin).status_code == 403
    assert client.get('/api/v1/orders/' + key, headers=tokens['other-operator']).status_code in {403, 404}
    for action in ['accept', 'start', 'ready']:
        result = client.post(f'/api/v1/orders/{key}/{action}', headers=operator, json={'expectedVersion': order['version']})
        assert result.status_code == 200, result.text
        order = result.json()
    result = client.post(f'/api/v1/orders/{key}/complete', headers=operator,
                         json={'expectedVersion': order['version'], 'method': 'manual', 'code': pickup})
    assert result.status_code == 200, result.text
    assert result.json()['status'] == 'completed'
    assert client.post(f'/api/v1/orders/{key}/complete', headers=operator,
                       json={'expectedVersion': order['version'], 'method': 'manual', 'code': pickup}).status_code == 409
    review = client.post(f'/api/v1/student/orders/{key}/review', headers=student, json={'rating': 5, 'comment': 'Buena atención'})
    assert review.status_code == 201, review.text
    assert review.json()['career'] == 'Desarrollo de Software'
    reviews = client.get('/api/v1/admin/reviews', headers=admin).json()
    assert reviews['pagination']['total'] == 1
    rid = reviews['data'][0]['id']
    followup = client.put(f'/api/v1/admin/reviews/{rid}/followup', headers=admin,
                          json={'status': 'resolved', 'assignee': 'Responsable', 'note': 'Revisado', 'expectedVersion': 0})
    assert followup.status_code == 200, followup.text
    saved = client.get(f'/api/v1/admin/reviews/{rid}/followup', headers=admin)
    assert saved.status_code == 200 and saved.json()['status'] == 'resolved'
    history = client.get(f'/api/v1/admin/reviews/{rid}/followup/history', headers=admin).json()
    assert history['pagination']['total'] == 1
    today = datetime.now(ZoneInfo('America/Mexico_City')).date().isoformat()
    summary = client.get(f'/api/v1/businesses/business-1/stats?from={today}&to={today}', headers=operator)
    assert summary.status_code == 200, summary.text
    assert summary.json()['totalSold'] == 35.5
    with app.state.db.sessions() as db:
        assert db.get(Product, 'product-1').stock == 9
        assert db.scalar(select(func.count()).select_from(OutboxEvent)) >= 5


def test_order_idempotency_and_atomic_failure(client, app, tokens):
    key = uuid4().hex
    first = create_order(client, tokens['student'], key=key, quantity=2)
    assert first.status_code == 201, first.text
    again = create_order(client, tokens['student'], key=key, quantity=2)
    assert again.status_code in {200, 201}, again.text
    assert again.json()['id'] == first.json()['id']
    assert create_order(client, tokens['student'], key=key, quantity=3).status_code == 409
    assert create_order(client, tokens['student'], quantity=99).status_code in {409, 422}
    with app.state.db.sessions() as db:
        assert db.get(Product, 'product-1').stock == 8
        assert db.scalar(select(func.count()).select_from(Order)) == 1
        assert db.scalar(select(func.count()).select_from(OrderItem)) == 1


def test_operator_catalog_changes_reach_student_without_cross_local_access(client, tokens):
    operator = tokens['operator']
    shops = client.get('/api/v1/admin/businesses', headers=tokens['master'])
    assert shops.status_code == 200 and shops.json()['pagination']['total'] == 2
    update = client.patch('/api/v1/businesses/business-1', headers=operator,
                          json={'name': 'Cafetería actualizada', 'category': 'Comida', 'description': 'Horario habitual', 'expectedVersion': 1})
    assert update.status_code == 200
    draft = {'name': 'Nuevo platillo', 'description': 'Preparado al momento', 'category': 'Comida',
             'price': 40.25, 'stock': 3, 'imageUrl': None, 'isAvailable': True, 'isFeatured': False}
    assert client.post('/api/v1/businesses/business-2/products', headers=operator, json=draft).status_code in {403, 404}
    created = client.post('/api/v1/businesses/business-1/products', headers=operator, json=draft)
    assert created.status_code == 201, created.text
    products = client.get('/api/v1/businesses/business-1/products', headers=operator)
    assert products.status_code == 200
    assert {p['id'] for p in products.json()['data']} == {'product-1', created.json()['id']}
    student_catalog = client.get('/api/v1/student/businesses/business-1/products', headers=tokens['student'])
    assert student_catalog.status_code == 200
    assert created.json()['id'] in {p['id'] for p in student_catalog.json()['data']}


@pytest.mark.postgres
def test_last_unit_concurrent_purchase(app, client, tokens):
    if app.state.db.engine.dialect.name != 'postgresql':
        pytest.skip('PostgreSQL is required to prove row locking across concurrent sessions')
    with app.state.db.sessions.begin() as db:
        db.get(Product, 'product-1').stock = 1
    barrier = Barrier(2)

    # Do not run application lifespan twice on the shared app; clients reuse its DB.
    def request(identity):
        c = TestClient(app, base_url=app.state.settings.public_origin)
        try:
            barrier.wait(timeout=10)
            return create_order(c, tokens[identity]).status_code
        finally:
            c.close()

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(request, ['student', 'other-student']))
    assert sorted(results) == [201, 409]
    with app.state.db.sessions() as db:
        assert db.get(Product, 'product-1').stock == 0
        assert db.scalar(select(func.count()).select_from(Order)) == 1


def test_websocket_isolation_and_revocation(client, app, tokens):
    origin = {'Origin': app.state.settings.public_origin}
    with client.websocket_connect('/api/v1/realtime', headers=origin) as ws:
        ws.send_json({'action': 'auth', 'token': tokens['operator']['Authorization'].removeprefix('Bearer ')})
        ws.send_json({'action': 'subscribe', 'topics': ['business:business-1:orders']})
        assert ws.receive_json()['type'] == 'subscribed'
        ws.send_json({'action': 'subscribe', 'topics': ['business:business-2:orders']})
        assert ws.receive_json()['type'] == 'unauthorized'
    with client.websocket_connect('/api/v1/realtime', headers=origin) as ws:
        ws.send_json({'action': 'auth', 'token': tokens['master']['Authorization'].removeprefix('Bearer ')})
        assert ws.receive_json()['type'] == 'unauthorized'


def test_error_privacy_and_origin(client):
    response = client.post('/api/v1/auth/login', json={'email': 'bad', 'password': 'private-password'}, headers={'Origin': 'http://evil.example'})
    assert response.status_code == 403
    response = client.post('/api/v1/auth/login', json={'email': 'bad', 'password': 'private-password'}, headers={'Origin': 'http://testserver'})
    assert response.status_code == 422
    assert 'private-password' not in response.text
    assert response.headers['Cache-Control'] == 'no-store'
