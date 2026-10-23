"""V3.2 acceptance with real HTTP, persistence, worker cycles and permissions."""
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import re
from uuid import uuid4

import pytest
from sqlalchemy import func, select

from snackup.admin_models import Review
from snackup.db import OutboxEvent
from snackup.identity_models import AccountAuditEvent
from snackup.jobs import run_cycle
from snackup.operation_models import Business, Order, Product
from snackup.v32_models import CartItem, Chat, ChatClosure, ChatMessage, Favorite, MealVoucherUse
from test_v3_contract import assert_response
from test_v3_reviews_media import completed_order, upload


@pytest.fixture
def clock(monkeypatch):
    current = [datetime(2026, 10, 23, 18, 0, tzinfo=timezone.utc)]  # noon campus
    from snackup import operations, v32_api, v32_chat, v32_services
    for module in (operations, v32_api, v32_chat, v32_services):
        monkeypatch.setattr(module, 'utcnow', lambda: current[0])
    return current


def buy(client, tokens, who='student', key=None, **changes):
    return client.post('/api/v1/orders', headers={**tokens[who], 'Idempotency-Key': key or str(uuid4())}, json={
        'businessId': 'business-1', 'items': [{'productId': 'product-1', 'quantity': 1}],
        'paymentMethod': 'Efectivo', 'expectedTotal': 35.5, **changes})


def ready(client, tokens, order):
    for action in ('accept', 'start', 'ready'):
        response = client.post(f"/api/v1/orders/{order['id']}/{action}", headers=tokens['operator'], json={})
        assert response.status_code == 200, response.text
    return response.json()


def test_all_previous_routes_and_fifteen_missing_routes_are_now_mounted(app):
    before = json.loads((Path(__file__).parents[1] / 'evidence/v32-current-inventory.json').read_text())
    current = {method.upper() + ' ' + re.sub(r'\{[^}]+\}', '{id}', path.removeprefix('/api/v1'))
               for path, item in app.openapi()['paths'].items() for method in item
               if method in {'get', 'post', 'patch', 'put', 'delete'}}
    assert set(before['runtimeRoutes']) <= current
    assert set(before['missingRoutes']) <= current


def test_cart_favorites_preserve_notes_and_use_current_prices_without_cross_user_access(client, tokens, app):
    path = '/api/v1/users/me/cart/items'
    saved = client.post(path, headers=tokens['student'], json={'productId': 'product-1', 'quantity': 2, 'notes': 'sin chile'})
    assert saved.status_code == 200
    item = assert_response('post', path, saved)
    updated = client.post(path, headers=tokens['student'], json={'productId': 'product-1', 'quantity': 3, 'notes': 'sin sal'})
    assert updated.json()['id'] == item['id'] and updated.json()['quantity'] == 3
    assert client.patch(path + '/' + item['id'], headers=tokens['other-student'], json={'quantity': 7}).status_code == 404
    assert client.patch(path + '/' + item['id'], headers=tokens['student'], json={'quantity': 0}).status_code == 422
    assert client.patch(path + '/' + item['id'], headers=tokens['student'], json={'notes': None}).status_code == 422
    assert client.get(path, headers=tokens['operator']).status_code == 403
    favorite = '/api/v1/users/me/favorites/product-1'
    assert client.put(favorite, headers=tokens['student'], json={'notes': 'sin chile'}).status_code == 200
    assert client.put(favorite, headers=tokens['student']).json()['notes'] == 'sin chile'
    client.patch('/api/v1/products/product-1', headers=tokens['operator'], json={'price': 40.0})
    view = client.get(path, headers=tokens['student']).json()['data'][0]
    assert view['product']['price'] == 40 and view['notes'] == 'sin sal'
    assert client.get('/api/v1/users/me/favorites', headers=tokens['other-student']).json()['data'] == []
    assert client.request('DELETE', '/api/v1/products/product-1', headers=tokens['operator'], json={}).status_code == 204
    view = client.get(path, headers=tokens['student']).json()['data'][0]
    assert view['product'] is None and not view['available']
    assert client.delete(path + '/' + item['id'], headers=tokens['student']).status_code == 204
    assert client.delete(favorite, headers=tokens['student']).status_code == 204
    with app.state.db.sessions() as db:
        assert not db.scalar(select(CartItem.id)) and not db.scalar(select(Favorite.id))


def test_search_static_routes_wildcard_escape_and_featured_limit(client, tokens, app):
    for i in range(4):
        result = client.post('/api/v1/businesses/business-1/products', headers=tokens['operator'],
                             json={'name': 'Torta ' + str(i), 'category': 'Comida', 'price': 20.0, 'isFeatured': True})
        assert result.status_code == (201 if i < 3 else 409), result.text
    assert client.get('/api/v1/products/search?q=torTA', headers=tokens['student']).json()['pagination']['total'] == 4
    assert client.get('/api/v1/products/search?q=%25', headers=tokens['student']).json()['data'] == []
    featured = client.get('/api/v1/products/featured', headers=tokens['student'])
    assert len(assert_response('get', '/api/v1/products/featured', featured)['data']) == 3
    denied = client.patch('/api/v1/products/product-1', headers=tokens['operator'], json={'isFeatured': True})
    assert denied.status_code == 409 and denied.json()['error']['code'] == 'FEATURED_LIMIT_REACHED'
    with app.state.db.sessions.begin() as db:
        db.get(Business, 'business-1').is_active = False
    assert client.get('/api/v1/products/search?q=torta', headers=tokens['student']).json()['data'] == []


def test_zero_stars_alias_is_single_business_rating_and_public_dto_is_private(client, tokens, app):
    order = completed_order(client, tokens)
    path = f"/api/v1/orders/{order['id']}/reviews"
    for score in (-1, 6, 0.5, True, '0'):
        result = client.post(path, headers=tokens['student'], json={'stars': score})
        assert result.status_code == 422 and result.json()['error']['code'] == 'INVALID_RATING'
    result = client.post(path, headers=tokens['student'], json={'stars': 0, 'comment': 'Experiencia de prueba'})
    assert result.status_code == 201, result.text
    assert result.json()['stars'] == result.json()['rating'] == 0
    assert client.post(path.replace('/reviews', '/rating'), headers=tokens['student'], json={'stars': 5}).status_code == 409
    public = client.get('/api/v1/businesses/business-1/ratings', headers=tokens['other-student'])
    row = assert_response('get', '/api/v1/businesses/{id}/ratings', public)['data'][0]
    assert row['stars'] == 0 and not {'userId', 'orderId', 'careerId', 'email'} & row.keys()
    shop = client.get('/api/v1/businesses/business-1', headers=tokens['student']).json()
    assert shop['averageRating'] == 0 and shop['totalRatings'] == 1
    assert client.get('/api/legacy/v1/admin/reviews', headers=tokens['admin']).status_code == 200
    with app.state.db.sessions() as db:
        assert db.scalar(select(func.count()).select_from(Review)) == 1


def test_scheduled_pickup_closure_postponement_and_deduplicated_alerts(client, tokens, app, clock):
    schedule = '/api/v1/businesses/business-1/closing-schedule'
    assert client.patch(schedule, headers=tokens['other-operator'], json={'autoCloseEnabled': False}).status_code == 403
    assert client.patch(schedule, headers=tokens['operator'], json={'autoCloseEnabled': True}).status_code == 422
    configured = client.patch(schedule, headers=tokens['operator'], json={'autoCloseEnabled': True, 'closeTimeLocal': '13:00'})
    assert configured.status_code == 200
    assert buy(client, tokens, scheduledPickupTime='2026-10-23T12:03:00-06:00').status_code == 422
    assert buy(client, tokens, scheduledPickupTime='2026-10-24T12:30:00-06:00').status_code == 422
    assert buy(client, tokens, scheduledPickupTime='2026-10-23T13:00:00-06:00').json()['error']['code'] == 'PICKUP_AFTER_CLOSING'
    assert buy(client, tokens, scheduledPickupTime='2026-10-23T12:30:00').status_code == 422
    order = buy(client, tokens, scheduledPickupTime='2026-10-23T12:30:00-06:00').json()
    assert order['scheduledPickupTime'].startswith('2026-10-23T18:30')
    assert run_cycle(app.state.db, app.state.settings, clock[0])['pickupAlerts'] == 0
    clock[0] += timedelta(minutes=20)
    assert run_cycle(app.state.db, app.state.settings, clock[0])['pickupAlerts'] == 1
    assert run_cycle(app.state.db, app.state.settings, clock[0])['pickupAlerts'] == 0
    postponed = client.post('/api/v1/businesses/business-1/postpone-closing', headers=tokens['operator'],
                            json={'until': '2026-10-23T14:00:00-06:00'})
    assert postponed.status_code == 200, postponed.text
    assert run_cycle(app.state.db, app.state.settings, clock[0] + timedelta(minutes=50))['closures'] == 0
    assert run_cycle(app.state.db, app.state.settings, clock[0] + timedelta(minutes=100))['closures'] == 1
    with app.state.db.sessions() as db:
        assert not db.get(Business, 'business-1').is_open
        assert db.get(Order, order['id']).status == 'pending'
        assert db.scalar(select(func.count()).select_from(OutboxEvent).where(OutboxEvent.event_type == 'order.pickup_soon')) == 1
        assert db.scalar(select(OutboxEvent.id).where(OutboxEvent.event_type == 'order.business_closed'))
    assert client.patch('/api/v1/businesses/business-1/status', headers=tokens['operator'], json={'isOpen': True}).status_code == 200
    assert run_cycle(app.state.db, app.state.settings, clock[0] + timedelta(minutes=110))['closures'] == 0
    with app.state.db.sessions() as db:
        assert db.get(Business, 'business-1').is_open


def test_not_picked_up_uses_later_scheduled_time_and_never_returns_stock(client, tokens, app, clock):
    order = buy(client, tokens, scheduledPickupTime=(clock[0] + timedelta(hours=1)).isoformat()).json()
    current = ready(client, tokens, order)
    path = f"/api/v1/orders/{order['id']}/cancel"
    clock[0] += timedelta(minutes=89)
    result = client.post(path, headers=tokens['operator'], json={'reason': 'not_picked_up'})
    assert result.status_code == 422 and result.json()['error']['code'] == 'PICKUP_TIMEOUT_NOT_REACHED'
    assert client.post(path, headers=tokens['student'], json={'reason': 'not_picked_up'}).status_code == 422
    clock[0] += timedelta(minutes=1)
    result = client.post(path, headers=tokens['operator'], json={'reason': 'not_picked_up', 'expectedVersion': current['version']})
    assert result.status_code == 200 and result.json()['status'] == 'cancelled'
    with app.state.db.sessions() as db:
        assert db.get(Product, 'product-1').stock == 9
        assert not db.get(Order, order['id']).stock_restored
    assert client.post(path, headers=tokens['operator'], json={'reason': 'not_picked_up'}).status_code == 400


def test_voucher_retries_cancellation_confirmation_and_consumption(client, tokens, app, clock):
    key = str(uuid4())
    first = buy(client, tokens, key=key, paymentMethod='ValeComida')
    assert first.status_code == 201, first.text
    order = first.json()
    assert buy(client, tokens, key=key, paymentMethod='ValeComida').json() == order
    assert buy(client, tokens, paymentMethod='ValeComida').json()['error']['code'] == 'MEAL_VOUCHER_ALREADY_USED'
    path = f"/api/v1/orders/{order['id']}"
    assert client.post(path + '/cancel', headers=tokens['student'],
                       json={'reason': 'user_other', 'notes': 'Cambio', 'voucherNotRedeemed': True}).status_code == 403
    assert client.post(path + '/cancel', headers=tokens['student'], json={'reason': 'user_other', 'notes': 'Cambio'}).status_code == 200
    assert buy(client, tokens, paymentMethod='ValeComida').status_code == 409
    release = path + '/meal-voucher/release'
    assert client.post(release, headers=tokens['student'], json={'notRedeemed': True}).status_code == 403
    assert client.post(release, headers=tokens['other-operator'], json={'notRedeemed': True}).status_code in (403, 404)
    assert client.post(release, headers=tokens['operator'], json={'notRedeemed': False}).status_code == 422
    for _ in range(2):
        assert client.post(release, headers=tokens['operator'], json={'notRedeemed': True}).status_code == 200
    result = buy(client, tokens, paymentMethod='ValeComida')
    assert result.status_code == 201, result.text
    new = result.json()
    ready(client, tokens, new)
    assert client.post(f"/api/v1/orders/{new['id']}/complete", headers=tokens['operator'],
                       json={'method': 'manual', 'code': new['pickupCode']}).status_code == 200
    assert buy(client, tokens, paymentMethod='ValeComida').status_code == 409
    with app.state.db.sessions() as db:
        assert sorted(db.scalars(select(MealVoucherUse.state))) == ['consumed', 'released']
        assert db.scalar(select(func.count()).select_from(AccountAuditEvent)
                         .where(AccountAuditEvent.action == 'meal_voucher.released')) == 1


def test_voucher_campus_midnight_new_day_and_expired_delivery(client, tokens, app, clock):
    clock[0] = datetime(2026, 10, 24, 5, 59, tzinfo=timezone.utc)  # 23:59 campus
    first = buy(client, tokens, paymentMethod='ValeComida').json()
    ready(client, tokens, first)
    clock[0] += timedelta(minutes=2)
    rejected = client.post(f"/api/v1/orders/{first['id']}/complete", headers=tokens['operator'],
                           json={'method': 'manual', 'code': first['pickupCode']})
    assert rejected.status_code == 422 and rejected.json()['error']['code'] == 'MEAL_VOUCHER_DATE_EXPIRED'
    assert buy(client, tokens, paymentMethod='ValeComida').status_code == 201
    with app.state.db.sessions() as db:
        assert [str(x) for x in db.scalars(select(MealVoucherUse.local_date).order_by(MealVoucherUse.local_date))] == ['2026-10-23', '2026-10-24']


def test_card_history_statistics_and_no_payment_processing(client, tokens, app, clock):
    order = buy(client, tokens, paymentMethod='Tarjeta').json()
    ready(client, tokens, order)
    assert order['paymentStatus'] == 'unverified'
    client.post(f"/api/v1/orders/{order['id']}/complete", headers=tokens['operator'],
                json={'method': 'manual', 'code': order['pickupCode']})
    history = client.get('/api/v1/users/me/orders/history', headers=tokens['student'])
    assert assert_response('get', '/api/v1/users/me/orders/history', history)['data'][0]['id'] == order['id']
    assert client.get('/api/v1/users/me/orders/history', headers=tokens['other-student']).json()['data'] == []
    stats = client.get('/api/v1/businesses/business-1/stats?from=2026-10-23&to=2026-10-24', headers=tokens['operator'])
    data = assert_response('get', '/api/v1/businesses/{id}/stats', stats)
    assert data['completed'] == 1 and data['totalSold'] == 35.5
    assert len(data['daily']) == 2 and data['daily'][1]['completed'] == 0
    assert data['topProducts'][0]['quantity'] == 1
    assert data['paymentMethods'] == [{'paymentMethod': 'Tarjeta', 'completed': 1, 'totalSold': 35.5}]


def test_business_cover_media_cannot_be_deleted_while_referenced(client, tokens):
    media = upload(client, tokens['operator'], 'business', {'businessId': 'business-1'}).json()
    result = client.patch('/api/v1/businesses/business-1', headers=tokens['operator'],
                          json={'coverImageUrl': media['url'], 'pickupTimeoutMinutes': 45})
    assert result.status_code == 200 and result.json()['pickupTimeoutMinutes'] == 45
    assert client.delete('/api/v1/media/' + media['id'], headers=tokens['operator']).status_code == 409
    assert client.patch('/api/v1/businesses/business-1', headers=tokens['operator'], json={'pickupTimeoutMinutes': 4}).status_code == 422


def test_chat_participants_discovery_private_outbox_and_physical_deletion(client, tokens, app):
    path = '/api/v1/businesses/business-1/chats'
    chat = client.post(path, headers=tokens['student'], json={}).json()
    assert client.post(path, headers=tokens['student'], json={}).json()['id'] == chat['id']
    assert client.post(path, headers=tokens['operator'], json={}).status_code == 422
    assert client.get(path, headers=tokens['operator']).json()['pagination']['total'] == 1
    assert client.get(path, headers=tokens['other-operator']).status_code == 403
    route = '/api/v1/chats/' + chat['id']
    for who in ('other-student', 'other-operator', 'admin'):
        assert client.get(route + '/messages', headers=tokens[who]).status_code == 404
        assert client.delete(route, headers=tokens[who]).status_code in (403, 404)
    body = {'text': 'Private-chat-fixture-do-not-retain'}
    assert client.post(route + '/messages', headers=tokens['student'], json=body).status_code == 201
    assert client.post(route + '/messages', headers=tokens['student'], json=body).status_code == 429
    assert client.get(route + '/messages', headers=tokens['operator']).json()['data'][0]['text'] == body['text']
    with app.state.db.sessions() as db:
        assert all(body['text'] not in json.dumps(row.data) for row in db.scalars(select(OutboxEvent)))
    for who in ('operator', 'student', 'operator'):
        assert client.delete(route, headers=tokens[who]).status_code == 204
    assert client.get(route + '/messages', headers=tokens['student']).status_code == 404
    with app.state.db.sessions() as db:
        assert db.get(Chat, chat['id']) is None and not db.scalar(select(ChatMessage.id))
        receipt = db.get(ChatClosure, chat['id'])
        assert receipt and receipt.student_proof != 'student'


def test_inactive_chat_worker_deletes_messages_and_reopening_gets_new_id(client, tokens, app, clock):
    chat = client.post('/api/v1/businesses/business-1/chats', headers=tokens['student'], json={}).json()
    route = '/api/v1/chats/' + chat['id']
    client.post(route + '/messages', headers=tokens['student'], json={'text': 'Temporal'})
    clock[0] += timedelta(hours=24)
    assert client.get(route + '/messages', headers=tokens['student']).status_code == 404
    assert run_cycle(app.state.db, app.state.settings, clock[0])['expiredChats'] == 1
    assert run_cycle(app.state.db, app.state.settings, clock[0])['expiredChats'] == 0
    assert client.delete(route, headers=tokens['student']).status_code == 204
    other = client.post('/api/v1/businesses/business-1/chats', headers=tokens['student'], json={}).json()
    assert other['id'] != chat['id']


def test_worker_restart_catches_up_previous_day_without_reopening(client, tokens, app, clock):
    with app.state.db.sessions.begin() as db:
        business = db.get(Business, 'business-1')
        business.auto_close_enabled = True
        business.close_time_local = '18:00'
        business.updated_at = clock[0]  # noon before last closing
    clock[0] += timedelta(hours=20)  # next day, 08:00 campus
    assert run_cycle(app.state.db, app.state.settings, clock[0])['closures'] == 1
    with app.state.db.sessions() as db:
        business = db.get(Business, 'business-1')
        assert not business.is_open and str(business.last_auto_close_date) == '2026-10-23'
    assert run_cycle(app.state.db, app.state.settings, clock[0])['closures'] == 0


def test_due_closing_blocks_orders_before_worker_and_manual_close_preserves_orders(client, tokens, app, clock):
    client.patch('/api/v1/businesses/business-1/closing-schedule', headers=tokens['operator'],
                 json={'autoCloseEnabled': True, 'closeTimeLocal': '13:00'})
    order = buy(client, tokens, scheduledPickupTime='2026-10-23T12:30:00-06:00').json()
    client.post('/api/v1/businesses/business-1/postpone-closing', headers=tokens['operator'],
                json={'until': '2026-10-23T14:00:00-06:00'})
    client.patch('/api/v1/businesses/business-1/status', headers=tokens['operator'], json={'isOpen': False})
    assert buy(client, tokens).json()['error']['code'] == 'BUSINESS_CLOSED'
    assert client.post(f"/api/v1/orders/{order['id']}/accept", headers=tokens['operator'], json={}).status_code == 200
    client.patch('/api/v1/businesses/business-1/status', headers=tokens['operator'], json={'isOpen': True})
    clock[0] += timedelta(hours=2)
    assert buy(client, tokens).json()['error']['code'] == 'BUSINESS_CLOSED'


def test_voucher_failure_rolls_back_order_number_and_inventory(client, tokens, app, clock):
    assert buy(client, tokens, paymentMethod='ValeComida').status_code == 201
    for _ in range(2):
        assert buy(client, tokens, paymentMethod='ValeComida').status_code == 409
    with app.state.db.sessions() as db:
        assert db.scalar(select(func.count()).select_from(Order)) == 1
        assert db.get(Business, 'business-1').next_order_number == 2
        assert db.get(Product, 'product-1').stock == 9
    next_order = buy(client, tokens, paymentMethod='Tarjeta')
    assert next_order.status_code == 201 and next_order.json()['orderNumber'] == 2
    assert client.get('/api/legacy/v1/student/orders', headers=tokens['student']).status_code == 200
