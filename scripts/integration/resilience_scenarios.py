"""Destructive fixtures only: called with the disposable app from live_backend.py."""
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
import json
from pathlib import Path
import time
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from uuid import uuid4


def run(app, settings, origin, password):
    from snackup.auth import hash_password, as_utc
    from snackup.db import utcnow
    from snackup.identity_models import User
    from snackup.operation_models import Business, Product, Order
    from snackup.jobs import run_cycle
    from snackup.v32_services import CAMPUS_ZONE
    from sqlalchemy import select
    assert origin.startswith('http://127.0.0.1:') and settings.environment == 'test'
    checks = []

    def request(method, path, body=None, token=None, key=None):
        headers = {'Origin': origin, 'Content-Type': 'application/json'}
        if token: headers['Authorization'] = 'Bearer ' + token
        if key: headers['Idempotency-Key'] = key
        req = Request(origin + path, data=json.dumps(body).encode() if body is not None else None,
                      headers=headers, method=method)
        try: response = urlopen(req, timeout=20)
        except HTTPError as error: response = error
        with response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else None

    with app.state.db.sessions.begin() as db:
        db.add(Business(id='resilience', name='Local resiliencia', is_open=True,
                        cafeteria_id='cafeteria', cafeteria_name='Cafetería universitaria'))
        db.flush()
        db.add(User(id='resilience-operator', email='resilience@staff.example.edu', display_name='Operador pruebas',
                    password_hash=hash_password(password), role='business', business_id='resilience',
                    is_active=True, email_verified=True, approval_status='approved'))
        db.add(Product(id='resilience-product', business_id='resilience', name='Torta prueba',
                       category='Comida', price='10.00', stock=40))
    def login(email):
        status, data = request('POST', '/api/legacy/v1/auth/login', {'email': email, 'password': password})
        assert status == 200, status
        return data['tokens']['accessToken']
    token = login('resilience@staff.example.edu')
    student = login('student@students.example.edu')
    body = {'businessId': 'resilience', 'items': [{'productId': 'resilience-product', 'quantity': 1}],
            'paymentMethod': 'Efectivo', 'expectedTotal': 10}
    with ThreadPoolExecutor(max_workers=4) as pool:
        purchases = list(pool.map(lambda _: request('POST', '/api/v1/orders', body, student, str(uuid4())), range(4)))
    sqlite = app.state.db.engine.dialect.name == 'sqlite'
    if sqlite:
        # SQLite has no SELECT FOR UPDATE. Record its conflict limitation;
        # retry fixture creation serially so independent UI fault tests can run.
        conflicts = sum(s == 409 for s, _ in purchases)
        assert all(s in (201, 409) for s, _ in purchases), purchases
        checks.append(f'SQLite diagnostic: {conflicts} concurrent creation conflicts; not production certification')
        purchases = [(s, d) if s == 201 else request('POST', '/api/v1/orders', body, student, str(uuid4())) for s, d in purchases]
    assert all(s == 201 for s, _ in purchases), [(s, d) for s, d in purchases]
    orders = [d for _, d in purchases]
    assert len({o['id'] for o in orders}) == len({o['orderNumber'] for o in orders}) == 4
    with app.state.db.sessions() as db:
        assert db.get(Product, 'resilience-product').stock == 36
    checks.append('4 purchases: unique IDs/numbers and exact stock' if sqlite else '4 concurrent purchases: unique IDs/numbers and exact stock')
    # Two operators may attempt the same old version: exactly one transition.
    order = orders[0]
    def accept(o):
        return request('POST', f"/api/legacy/v1/orders/{o['id']}/accept", {'expectedVersion': o['version']}, token)
    with ThreadPoolExecutor(max_workers=2) as pool:
        collision = list(pool.map(lambda _: accept(order), range(2)))
    assert sorted(s for s, _ in collision) == [200, 409], collision
    checks.append('same order concurrent accept: one success, one conflict')
    with ThreadPoolExecutor(max_workers=2) as pool:
        distinct = list(pool.map(accept, orders[1:3]))
    assert all(s == 200 for s, _ in distinct), distinct
    checks.append('different orders can be accepted concurrently')

    # Keep one pending order and prepare another for browser delivery-loss tests.
    current = collision[0][1] if collision[0][0] == 200 else collision[1][1]
    for action in ('start', 'ready'):
        status, current = request('POST', f"/api/legacy/v1/orders/{order['id']}/{action}", {'expectedVersion': current['version']}, token)
        assert status == 200, (action, status, current)

    # Exercise the production scheduler cycle with explicit boundary times,
    # then with real elapsed time. No system clock is changed.
    business_path = '/api/v1/businesses/resilience'
    status, business = request('GET', business_path, token=token)
    now = utcnow()
    due = (now + timedelta(minutes=1)).replace(second=0, microsecond=0)
    local_due = due.astimezone(CAMPUS_ZONE)
    assert local_due.date() == now.astimezone(CAMPUS_ZONE).date(), 'Run away from campus midnight'
    status, _ = request('PATCH', business_path + '/closing-schedule',
        {'expectedVersion': business['version'], 'autoCloseEnabled': True, 'closeTimeLocal': local_due.strftime('%H:%M')}, token)
    assert status == 200
    _, business = request('GET', business_path, token=token)
    postponed = due + timedelta(seconds=5)
    status, _ = request('POST', business_path + '/postpone-closing',
        {'expectedVersion': business['version'], 'until': postponed.isoformat()}, token)
    assert status == 200
    # Other businesses from baseline tests must not influence these assertions.
    with app.state.db.sessions.begin() as db:
        for b in db.scalars(select(Business).where(Business.id != 'resilience')):
            b.auto_close_enabled = False
    run_cycle(app.state.db, settings, now=due)
    with app.state.db.sessions() as db:
        assert db.get(Business, 'resilience').is_open
        before = {o.id: o.status for o in db.scalars(select(Order).where(Order.business_id == 'resilience'))}
    print('Waiting for actual scheduled closure (at most 65 seconds).', flush=True)
    deadline = time.monotonic() + 70
    while True:
        run_cycle(app.state.db, settings)
        with app.state.db.sessions() as db:
            closed = not db.get(Business, 'resilience').is_open
        if closed: break
        assert time.monotonic() < deadline, 'Scheduler did not close the business'
        time.sleep(.25)
    assert utcnow() >= postponed
    with app.state.db.sessions() as db:
        assert {o.id: o.status for o in db.scalars(select(Order).where(Order.business_id == 'resilience'))} == before
        closed_version = db.get(Business, 'resilience').version
    run_cycle(app.state.db, settings)
    with app.state.db.sessions() as db:
        assert db.get(Business, 'resilience').version == closed_version
    checks.append('real-time scheduled closure honors postponement, preserves orders and is idempotent')
    status, _ = request('POST', '/api/v1/orders', body, student, str(uuid4()))
    assert status == 409, status
    checks.append('closed business rejects new purchases')
    _, business = request('GET', '/api/legacy/v1/businesses/resilience', token=token)
    status, _ = request('PATCH', '/api/legacy/v1/businesses/resilience/status',
        {'expectedVersion': business['version'], 'isOpen': True}, token)
    assert status == 200
    run_cycle(app.state.db, settings)
    with app.state.db.sessions() as db:
        assert db.get(Business, 'resilience').is_open
    checks.append('manual reopening after processed closure remains open')
    output = Path('build/live-backend')
    output.mkdir(parents=True, exist_ok=True)
    (output / 'resilience-api.json').write_text(json.dumps({'passed': True, 'checks': checks,
        'database': app.state.db.engine.dialect.name,
        'loadCertification': False}, indent=2), encoding='utf-8')
    return {'readyId': order['id'], 'readyCode': order['pickupCode'], 'pendingId': orders[3]['id']}
