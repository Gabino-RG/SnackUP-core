"""Cross-module acceptance: attribution, aggregates, owned storage and rollback."""
import io
from concurrent.futures import ThreadPoolExecutor
from threading import Event
from uuid import uuid4

import jwt
from PIL import Image
import pytest
from sqlalchemy import event, func, select, update

from snackup.admin_models import Review
from snackup.db import utcnow
from snackup.identity_models import AccountAuditEvent, RefreshSession
from snackup.operation_models import MediaFile, Order, Product
from snackup.review_models import ProductReview

pytestmark = pytest.mark.v3


def completed_order(client, tokens):
    response = client.post('/api/v1/orders', headers={**tokens['student'], 'Idempotency-Key': str(uuid4())},
                           json={'businessId': 'business-1', 'items': [{'productId': 'product-1', 'quantity': 1}],
                                 'expectedTotal': 35.5, 'paymentMethod': 'Efectivo'})
    assert response.status_code == 201
    order = response.json()
    for action in ('accept', 'start', 'ready', 'complete'):
        body = {'method': 'manual', 'code': order['pickupCode']} if action == 'complete' else {}
        result = client.post(f"/api/v1/orders/{order['id']}/{action}", headers=tokens['operator'], json=body)
        assert result.status_code == 200
    return order


def test_rating_preserves_academic_opinion_and_server_aggregates(client, tokens, app):
    order = completed_order(client, tokens)
    path = f"/api/v1/orders/{order['id']}/rating"
    assert client.post(path, headers=tokens['other-student'], json={'rating': 5}).status_code == 404
    assert client.post(path, headers=tokens['student'], json={'rating': 5, 'careerId': 'invented'}).status_code == 422
    rated = client.post(path, headers=tokens['student'], json={'rating': 4, 'foodRating': 5, 'comment': 'Bien'})
    assert rated.status_code == 201
    assert client.post(path, headers=tokens['student'], json={'rating': 1}).status_code == 409
    shop = client.get('/api/v1/businesses/business-1', headers=tokens['student']).json()
    assert (shop['averageRating'], shop['totalRatings'], shop['totalOrders']) == (4, 1, 1)
    own = client.get(f"/api/v1/orders/{order['id']}", headers=tokens['student']).json()
    assert own['isRated'] and own['version'] == 6
    public = client.get('/api/v1/admin/reviews', headers=tokens['admin']).json()['data'][0]
    assert public['careerId'] == 'career-1'
    assert not set(public) & {'userId', 'email', 'orderId', 'numeroDeControl'}
    with app.state.db.sessions() as db:
        assert db.scalar(select(func.count()).select_from(Review)) == 1


def test_product_reviews_atomic_purchase_scope_and_privacy(client, tokens, app):
    order = completed_order(client, tokens)
    path = f"/api/v1/orders/{order['id']}/reviews"
    bad = {'reviews': [{'productId': 'product-1', 'rating': 5}, {'productId': 'not-purchased', 'rating': 1}]}
    assert client.post(path, headers=tokens['student'], json=bad).status_code == 422
    with app.state.db.sessions() as db:
        assert db.scalar(select(func.count()).select_from(ProductReview)) == 0
    payload = {'reviews': [{'productId': 'product-1', 'rating': 5, 'comment': 'Buena torta'}]}
    assert client.post(path, headers=tokens['student'], json=payload).status_code == 201
    assert client.post(path, headers=tokens['student'], json=payload).status_code == 409
    product = client.get('/api/v1/businesses/business-1/products', headers=tokens['student']).json()['data'][0]
    assert product['averageRating'] == 5 and product['totalReviews'] == 1
    reviews = client.get('/api/v1/products/product-1/reviews', headers=tokens['other-student']).json()
    assert client.get('/api/v1/products/product-1/reviews', headers=tokens['other-operator']).status_code == 403
    assert reviews['pagination']['total'] == 1
    assert not set(reviews['data'][0]) & {'orderId', 'userId', 'email', 'numeroDeControl'}
    assert not client.get(f"/api/v1/orders/{order['id']}", headers=tokens['student']).json()['isRated']


def png():
    output = io.BytesIO()
    Image.new('RGB', (120, 80), 'green').save(output, 'PNG')
    return output.getvalue()


def upload(client, headers, purpose='avatar', data=None):
    return client.post('/api/v1/media', headers=headers, files={'file': ('untrusted.png', png(), 'image/png')},
                       data={'purpose': purpose, **(data or {})})


def test_media_owned_avatar_attachment_and_deletion(client, tokens, app):
    response = upload(client, tokens['student'])
    assert response.status_code == 201
    media = response.json()
    assert (media['width'], media['height']) == (120, 80)
    assert client.get(media['url']).headers['content-type'] == 'image/webp'
    profile = client.get('/api/v1/users/me', headers=tokens['student']).json()
    body = {'avatarUrl': media['url'], 'expectedVersion': profile['version']}
    assert client.patch('/api/v1/users/me', headers=tokens['other-student'], json=body).status_code == 422
    linked = client.patch('/api/v1/users/me', headers=tokens['student'], json=body)
    assert linked.status_code == 200
    route = '/api/v1/media/' + media['id']
    assert client.delete(route, headers=tokens['other-student']).status_code == 403
    assert client.delete(route, headers=tokens['admin']).status_code == 403
    assert client.delete(route, headers=tokens['student']).status_code == 409
    assert client.patch('/api/v1/users/me', headers=tokens['student'],
                        json={'avatarUrl': None, 'expectedVersion': linked.json()['version']}).status_code == 200
    assert client.delete(route, headers=tokens['student']).status_code == 204
    assert client.delete(route, headers=tokens['student']).status_code == 204
    assert client.get(media['url']).status_code == 404
    with app.state.db.sessions() as db:
        assert db.get(MediaFile, media['id']).deleted_at is not None


def test_media_purpose_scope_real_mime_and_limit(client, tokens, app):
    assert upload(client, tokens['student'], 'product').status_code == 403
    assert upload(client, tokens['operator'], 'business', {'businessId': 'business-2'}).status_code == 403
    assert upload(client, tokens['admin'], 'business', {'businessId': 'business-1'}).status_code == 201
    assert upload(client, tokens['student'], 'review').status_code == 201
    assert upload(client, tokens['operator'], 'review').status_code == 403
    invalid = client.post('/api/v1/media', headers=tokens['student'], data={'purpose': 'avatar'},
                          files={'file': ('fake.jpg', png(), 'image/jpeg')})
    assert invalid.status_code == 422
    oversized = client.post('/api/v1/media', headers=tokens['student'], data={'purpose': 'avatar'},
                            files={'file': ('huge.png', b'x' * (5 * 1024 * 1024 + 1), 'image/png')})
    assert oversized.status_code == 413
    with app.state.db.sessions() as db:
        assert db.scalar(select(func.count()).select_from(MediaFile)) == 2


def test_failed_metadata_transaction_removes_staged_image(client, tokens, app, monkeypatch):
    from snackup.errors import ApiError
    def reject_metadata(*args, **kwargs):
        raise ApiError(409, 'TEST_CONFLICT')
    monkeypatch.setattr('snackup.v3_media.MediaFile', reject_metadata)
    assert upload(client, tokens['student']).status_code == 409
    assert list(app.state.settings.media_dir.iterdir()) == []


def test_failed_pickup_is_audited_after_order_rollback(client, tokens, app):
    response = client.post('/api/v1/orders', headers={**tokens['student'], 'Idempotency-Key': str(uuid4())},
                           json={'businessId': 'business-1', 'items': [{'productId': 'product-1', 'quantity': 1}],
                                 'expectedTotal': 35.5})
    order = response.json()
    for action in ('accept', 'start', 'ready'):
        assert client.post(f"/api/v1/orders/{order['id']}/{action}", headers=tokens['operator'], json={}).status_code == 200
    result = client.post(f"/api/v1/orders/{order['id']}/complete", headers=tokens['operator'],
                         json={'method': 'manual', 'code': 'INCORRECTO'})
    assert result.status_code == 422
    assert 'INCORRECTO' not in result.text
    assert client.get(f"/api/v1/orders/{order['id']}", headers=tokens['student']).json()['status'] == 'ready'
    with app.state.db.sessions() as db:
        event = db.scalar(select(AccountAuditEvent).where(AccountAuditEvent.action == 'pickup.verification_failed'))
        assert event is not None and event.target_id == order['id']
        assert event.data == {'method': 'manual'}


@pytest.mark.postgres
@pytest.mark.parametrize('action', ['rating', 'reviews'])
def test_review_waiting_for_order_observes_session_revocation(client, tokens, app, action):
    from test_operations_concurrency import require_postgres
    require_postgres(app)
    order = completed_order(client, tokens)
    session_id = jwt.decode(tokens['student']['Authorization'].split()[1],
                            options={'verify_signature': False})['sid']
    payload = {'rating': 5} if action == 'rating' else {'reviews': [{'productId': 'product-1', 'rating': 5}]}
    waiting = Event()

    def observes_order_lock(connection, cursor, statement, parameters, context, executemany):
        if 'from orders' in statement.lower() and 'for update' in statement.lower():
            waiting.set()

    engine = app.state.db.engine
    with ThreadPoolExecutor(max_workers=1) as executor:
        try:
            with app.state.db.sessions.begin() as locked:
                locked.scalar(select(Order).where(Order.id == order['id']).with_for_update())
                event.listen(engine, 'before_cursor_execute', observes_order_lock)
                future = executor.submit(client.post, f"/api/v1/orders/{order['id']}/{action}",
                                         headers=tokens['student'], json=payload)
                assert waiting.wait(5), 'The review must wait for the existing order lock.'
                locked.execute(update(RefreshSession).where(RefreshSession.id == session_id)
                               .values(revoked_at=utcnow()))
            result = future.result(timeout=10)
        finally:
            event.remove(engine, 'before_cursor_execute', observes_order_lock)
    assert result.status_code == 401
    with app.state.db.sessions() as db:
        assert db.scalar(select(func.count()).select_from(Review)) == 0
        assert db.scalar(select(func.count()).select_from(ProductReview)) == 0
        assert db.get(Order, order['id']).version == 5
