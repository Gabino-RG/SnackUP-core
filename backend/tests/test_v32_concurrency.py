"""V3.2 races require PostgreSQL; SQLite cannot certify row-lock behavior."""
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from threading import Barrier
from uuid import uuid4

import pytest
from sqlalchemy import func, select

from snackup.db import OutboxEvent, utcnow
from snackup.jobs import run_cycle
from snackup.operation_models import Order, Product
from snackup.v32_models import Chat, MealVoucherUse
from test_operations_concurrency import concurrent, require_postgres
from test_v32_features import buy, ready

pytestmark = pytest.mark.postgres


def test_global_voucher_uniqueness_across_two_businesses(app, client, tokens):
    require_postgres(app)
    with app.state.db.sessions.begin() as db:
        db.add(Product(id='product-2', business_id='business-2', name='Otro', category='Comida', price=35.5, stock=10))
    def command(business, product):
        return ('POST', '/api/v1/orders', {'headers': {**tokens['student'], 'Idempotency-Key': str(uuid4())}, 'json': {
            'businessId': business, 'items': [{'productId': product, 'quantity': 1}],
            'expectedTotal': 35.5, 'paymentMethod': 'ValeComida'}})
    result = concurrent(app, command('business-1', 'product-1'), command('business-2', 'product-2'))
    assert sorted(x.status_code for x in result) == [201, 409], [x.text for x in result]
    assert next(x for x in result if x.status_code == 409).json()['error']['code'] == 'MEAL_VOUCHER_ALREADY_USED'
    with app.state.db.sessions() as db:
        assert db.scalar(select(func.count()).select_from(Order)) == 1
        assert db.scalar(select(func.count()).select_from(MealVoucherUse)) == 1
        assert db.scalar(select(func.sum(Product.stock))) == 19


def test_legacy_and_v3_catalog_share_the_three_featured_limit(app, client, tokens):
    require_postgres(app)
    with app.state.db.sessions.begin() as db:
        for i in range(2):
            db.add(Product(id='highlight-' + str(i), business_id='business-1', name='Featured', category='Comida',
                           price=20, is_featured=True))
    canonical = ('POST', '/api/v1/businesses/business-1/products', {'headers': tokens['operator'],
        'json': {'name': 'V3', 'category': 'Comida', 'price': 20.0, 'isFeatured': True}})
    legacy = ('POST', '/api/legacy/v1/businesses/business-1/products', {'headers': tokens['operator'],
        'json': {'name': 'Legacy', 'description': '', 'category': 'Comida', 'price': 20.0, 'imageUrl': None,
                 'isAvailable': True, 'isFeatured': True}})
    result = concurrent(app, canonical, legacy)
    assert sorted(x.status_code for x in result) == [201, 409], [x.text for x in result]
    with app.state.db.sessions() as db:
        assert db.scalar(select(func.count()).select_from(Product).where(Product.is_featured.is_(True))) == 3


def test_two_sides_open_same_chat_once(app, client, tokens):
    require_postgres(app)
    order = buy(client, tokens).json()
    def command(who):
        return ('POST', '/api/v1/businesses/business-1/chats', {'headers': tokens[who], 'json': {'orderId': order['id']}})
    a, b = concurrent(app, command('student'), command('operator'))
    assert a.status_code == b.status_code == 200, (a.text, b.text)
    assert a.json()['id'] == b.json()['id']
    with app.state.db.sessions() as db:
        assert db.scalar(select(func.count()).select_from(Chat)) == 1


def test_two_workers_claim_one_pickup_alert(app, client, tokens):
    require_postgres(app)
    order = buy(client, tokens).json()
    now = utcnow()
    with app.state.db.sessions.begin() as db:
        db.get(Order, order['id']).scheduled_pickup_time = now + timedelta(minutes=9)
    barrier = Barrier(2)
    def work():
        barrier.wait(timeout=10)
        return run_cycle(app.state.db, app.state.settings, now)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: work(), range(2)))
    assert sum(x['pickupAlerts'] for x in results) == 1
    with app.state.db.sessions() as db:
        assert db.scalar(select(func.count()).select_from(OutboxEvent).where(OutboxEvent.event_type == 'order.pickup_soon')) == 1


def test_delivery_and_no_pickup_cancellation_have_one_terminal_result(app, client, tokens):
    require_postgres(app)
    order = buy(client, tokens).json()
    ready(client, tokens, order)
    with app.state.db.sessions.begin() as db:
        db.get(Order, order['id']).ready_at = utcnow() - timedelta(hours=1)
    path = '/api/v1/orders/' + order['id']
    complete = ('POST', path + '/complete', {'headers': tokens['operator'], 'json': {'method': 'manual', 'code': order['pickupCode']}})
    cancel = ('POST', path + '/cancel', {'headers': tokens['operator'], 'json': {'reason': 'not_picked_up'}})
    result = concurrent(app, complete, cancel)
    assert sorted(x.status_code for x in result) == [200, 400], [x.text for x in result]
    with app.state.db.sessions() as db:
        assert db.get(Order, order['id']).status in ('completed', 'cancelled')
        assert db.get(Product, 'product-1').stock == 9
