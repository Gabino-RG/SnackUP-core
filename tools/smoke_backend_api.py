"""Smoke-test the pinned backend with synthetic data in a disposable SQLite DB.
Run with the isolated backend Python environment, never against production.
"""
import argparse
import json
from pathlib import Path
import secrets
import sys
import tempfile
from uuid import uuid4

parser = argparse.ArgumentParser()
parser.add_argument('--backend', default='build/api-smoke/source/backend')
parser.add_argument('--report', default='build/api-smoke/result.json')
args = parser.parse_args()
sys.path.insert(0, str(Path(args.backend).resolve()))
from fastapi.testclient import TestClient
from snackup.config import Settings
from snackup.main import create_app
from snackup.db import Base
from snackup.auth import hash_password
from snackup.identity_models import User, Career, AcademicRecord
from snackup.operation_models import Business, Product

checks = []
def check(condition, name):
    if not condition:
        raise AssertionError(name)
    checks.append(name)

run_root = Path('build/api-smoke/runs')
run_root.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(dir=run_root) as temporary:
    folder = Path(temporary).resolve()
    settings = Settings(environment='test', database_url='sqlite:///' + (folder / 'test.db').as_posix(),
        secret_key='isolated-' + secrets.token_hex(32), public_origin='http://testserver',
        admin_email_domains='staff.example.edu', student_email_domains='students.example.edu',
        media_dir=folder / 'media', background_events=False, redis_url='', push_enabled=False, smtp_host='')
    app = create_app(settings)
    Base.metadata.create_all(app.state.db.engine)
    password = secrets.token_urlsafe(24)
    password_hash = hash_password(password)
    with app.state.db.sessions.begin() as db:
        db.add(Career(id='career', name='Carrera de prueba'))
        db.flush()
        db.add(Business(id='cafe', name='Local de prueba', cafeteria_id='campus', cafeteria_name='Campus de prueba', is_open=True))
        db.flush()
        for identity, role in [('student', 'user'), ('other', 'user'), ('kitchen', 'business')]:
            email = identity + ('@staff.example.edu' if role == 'business' else '@students.example.edu')
            db.add(User(id=identity, email=email, display_name='Persona de prueba', password_hash=password_hash,
                role=role, business_id='cafe' if role == 'business' else None,
                is_active=True, email_verified=True, approval_status='approved'))
            if role == 'user':
                db.add(AcademicRecord(email=email, institutional_id='TEST-' + identity, display_name='Alumno de prueba',
                    kind='student', career_id='career', source='isolated client integration smoke'))
        db.add(Product(id='food', business_id='cafe', name='Platillo de prueba', category='Comida', price='35.50', stock=2))
    try:
        with TestClient(app, base_url='http://testserver') as client:
            origin = {'Origin': 'http://testserver'}
            def login(identity, staff=False):
                response = client.post('/api/v1/auth/login', json={'email': identity + ('@staff.example.edu' if staff else '@students.example.edu'), 'password': password}, headers=origin)
                check(response.status_code == 200, 'login-' + identity)
                return response.json()
            session = login('student')
            check(session['user']['role'] == 'ALUMNO', 'student-role')
            check(session['tokens'].get('refreshToken') is None, 'web-refresh-only-in-cookie')
            headers = {'Authorization': 'Bearer ' + session['tokens']['accessToken'], **origin}
            businesses = client.get('/api/v1/businesses?page=1&limit=100', headers=headers)
            check(businesses.status_code == 200 and businesses.json()['data'][0]['id'] == 'cafe', 'v3-businesses')
            products = client.get('/api/v1/businesses/cafe/products?isAvailable=true&page=1&limit=100', headers=headers)
            check(products.status_code == 200 and products.json()['data'][0]['price'] == 35.5, 'v3-products')
            key = str(uuid4())
            body = {'businessId': 'cafe', 'items': [{'productId': 'food', 'quantity': 1, 'notes': 'Sin cebolla'}],
                'paymentMethod': 'Efectivo', 'expectedTotal': 35.5}
            created = client.post('/api/v1/orders', json=body, headers={**headers, 'Idempotency-Key': key})
            check(created.status_code == 201, 'v3-order-create')
            order = created.json()
            retried = client.post('/api/v1/orders', json=body, headers={**headers, 'Idempotency-Key': key})
            check(retried.status_code == 201 and retried.json()['id'] == order['id'], 'idempotent-retry-same-order')
            with app.state.db.sessions() as db:
                check(db.get(Product, 'food').stock == 1, 'single-stock-reservation')
            history = client.get('/api/legacy/v1/student/orders?page=1&limit=100', headers=headers)
            check(history.status_code == 200 and history.json()['data'][0]['id'] == order['id'], 'legacy-history-accepts-v3-session')
            kitchen = login('kitchen', staff=True)
            kitchen_headers = {'Authorization': 'Bearer ' + kitchen['tokens']['accessToken'], **origin}
            for action in ['accept', 'start', 'ready']:
                result = client.post(f"/api/v1/orders/{order['id']}/{action}", json={'expectedVersion': order['version']}, headers=kitchen_headers)
                check(result.status_code == 200, 'kitchen-' + action)
                order = result.json()
            own = client.get('/api/v1/orders/' + order['id'], headers=headers)
            check(own.status_code == 200 and own.json()['status'] == 'ready' and bool(own.json()['pickupCode']), 'student-pickup-code')
            completed = client.post('/api/v1/orders/' + order['id'] + '/complete',
                json={'expectedVersion': order['version'], 'method': 'qr', 'code': own.json()['pickupCode']}, headers=kitchen_headers)
            check(completed.status_code == 200 and completed.json()['status'] == 'completed', 'kitchen-delivery')
            rating = client.post('/api/v1/orders/' + order['id'] + '/rating', json={'rating': 5, 'comment': 'Muy buena atención'}, headers=headers)
            check(rating.status_code == 201, 'restaurant-rating')
            review_body = {'reviews': [{'productId': 'food', 'rating': 4, 'comment': 'Muy rico'}]}
            review = client.post('/api/v1/orders/' + order['id'] + '/reviews', json=review_body, headers=headers)
            check(review.status_code == 201, 'food-review')
            duplicate = client.post('/api/v1/orders/' + order['id'] + '/reviews', json=review_body, headers=headers)
            check(duplicate.status_code == 409, 'duplicate-review-rejected')
            public = client.get('/api/v1/products/food/reviews?page=1&limit=100', headers=headers)
            check(public.status_code == 200 and len(public.json()['data']) == 1, 'product-reviews-list')
            check(not ({'userId', 'email', 'orderId'} & set(public.json()['data'][0])), 'public-review-does-not-expose-identity')
            latest = client.get('/api/v1/orders/' + order['id'], headers=headers)
            check(latest.json()['isRated'] is True and latest.json()['status'] == 'completed', 'authoritative-completed-rated-order')
            # Restore the student's cookie after the kitchen fixture login.
            login('student')
            refresh = client.post('/api/v1/auth/refresh', json={}, headers=origin)
            check(refresh.status_code == 200 and 'accessToken' in refresh.json()['tokens'], 'cookie-refresh')
            logout = client.post('/api/v1/auth/logout', json={}, headers=origin)
            check(logout.status_code == 204, 'cookie-logout')
    finally:
        app.state.db.dispose()
report = {'backendRef': '1c3459b', 'database': 'disposable SQLite, synthetic identities', 'checksPassed': len(checks), 'checks': checks,
    'limitations': ['No production server or real student data used', 'Does not test PostgreSQL concurrency, SMTP delivery or browser Socket.IO']}
output = Path(args.report)
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'checksPassed': len(checks), 'report': str(output)}, ensure_ascii=False))
