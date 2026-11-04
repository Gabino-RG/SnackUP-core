"""HTTP acceptance for the isolated, seeded SnackUP installation.

Uses three independent cookie jars. Creates one real test order and keeps its
delivery/reviews as demonstration evidence. Never accepts a remote server.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from decimal import Decimal
from http.cookiejar import CookieJar
import json
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import quote, urlsplit
from urllib.request import HTTPCookieProcessor, Request, build_opener
from uuid import uuid4


class Client:
    def __init__(self, origin, prefix):
        self.origin, self.prefix, self.token = origin, prefix, None
        self.opener = build_opener(HTTPCookieProcessor(CookieJar()))

    def request(self, method, path, body=None, *, expected=200, key=None):
        headers = {'Origin': self.origin, 'Accept': 'application/json'}
        if self.token:
            headers['Authorization'] = 'Bearer ' + self.token
        if key:
            headers['Idempotency-Key'] = key
        data = None
        if body is not None:
            headers['Content-Type'] = 'application/json'
            data = json.dumps(body).encode('utf-8')
        req = Request(self.origin + self.prefix + path, data=data,
                      headers=headers, method=method)
        try:
            response = self.opener.open(req, timeout=25)
        except HTTPError as error:
            response = error
        with response:
            raw = response.read()
            value = json.loads(raw) if raw else None
            status = response.status
        if expected is not None and status != expected:
            code = value.get('error', {}).get('code') if isinstance(value, dict) else None
            raise AssertionError(f'{method} {path}: expected {expected}, got {status} ({code})')
        return (status, value) if expected is None else value

    def login(self, email):
        result = self.request('POST', '/auth/login',
                              {'email': email, 'password': 'SnackUP-Prueba-V32!'})
        self.token = result['tokens']['accessToken']
        return self.request('GET', '/users/me')

    def all(self, path):
        result = []
        for page in range(1, 101):
            # Product-review endpoints cap pages at 100; this also fits the
            # legacy lists, whose upper bound is 200.
            value = self.request('GET', path + ('&' if '?' in path else '?') + f'page={page}&limit=100')
            if isinstance(value, list):
                return value
            result.extend(value['data'])
            if page >= value['pagination']['totalPages']:
                return result
        raise AssertionError('Pagination exceeded isolated-test limit')


def run(origin, report):
    student = Client(origin, '/api/v1')
    kitchen = Client(origin, '/api/legacy/v1')
    admin = Client(origin, '/api/legacy/v1')
    student.login('alumno.demo@utsjr.edu.mx')
    kitchen.login('operator@staff.example.edu')
    admin.login('master@staff.example.edu')
    checks = report['checks']
    checks.append('Independent student, kitchen and administrator sessions')
    business_id = 'integration-local'
    business = kitchen.request('GET', '/businesses/' + business_id)
    assert business['isOpen'], 'Open the isolated demonstration local before testing'
    products = student.all('/businesses/' + business_id + '/products')
    product = next((p for p in products if p['isAvailable'] and
                    (p['stock'] is None or p['stock'] > 0)), None)
    assert product is not None, 'No available seeded test product'
    pid = quote(product['id'], safe='')
    product_before = student.request('GET', '/products/' + pid)
    marker = 'Integración HTTP ' + uuid4().hex[:12]
    purchase = {'businessId': business_id,
                'items': [{'productId': product['id'], 'quantity': 1, 'notes': marker}],
                'paymentMethod': 'Efectivo', 'expectedTotal': float(Decimal(str(product['price'])))}
    key = str(uuid4())
    order = student.request('POST', '/orders', purchase, expected=201, key=key)
    oid = quote(order['id'], safe='')
    report['orderId'] = order['id']
    report['productId'] = product['id']
    replay = student.request('POST', '/orders', purchase, expected=201, key=key)
    assert replay == order, 'Idempotent purchase returned a different order'
    after = student.request('GET', '/products/' + pid)
    if product_before['stock'] is not None:
        assert after['stock'] == product_before['stock'] - 1, 'Stock reservation was not exactly one'
    checks.append('Student purchase reserves stock once; same idempotency key returns same order')

    active = kitchen.all('/businesses/' + business_id + '/orders/active')
    current = next(o for o in active if o['id'] == order['id'])
    assert current['status'] == 'pending'
    checks.append('Canonical student order is visible in the legacy Kitchen API')

    student.request('GET', '/admin/reviews', expected=403)
    kitchen.request('GET', '/admin/reviews', expected=403)
    admin.request('GET', '/businesses/' + business_id + '/orders/active', expected=403)
    checks.append('Student/Kitchen cannot read Administration; administrator cannot operate Kitchen')

    # Two requests from the same old version must produce just one transition.
    old_version = current['version']
    def accept(_):
        peer = Client(origin, '/api/legacy/v1')
        peer.token = kitchen.token
        return peer.request('POST', '/orders/' + oid + '/accept',
                            {'expectedVersion': old_version}, expected=None)
    with ThreadPoolExecutor(max_workers=2) as pool:
        accepted = list(pool.map(accept, range(2)))
    assert sorted(status for status, _ in accepted) == [200, 409], 'Concurrent acceptance was not exclusive'
    current = next(value for status, value in accepted if status == 200)
    checks.append('Concurrent acceptance: one success and one version conflict')
    for action, state in [('start', 'preparing'), ('ready', 'ready')]:
        current = kitchen.request('POST', '/orders/' + oid + '/' + action,
                                  {'expectedVersion': current['version']})
        assert current['status'] == state
        visible = student.request('GET', '/orders/' + oid)
        assert visible['status'].lower() == state, 'Student sees a different order state'
    checks.append('Kitchen preparation/readiness visible to student through authoritative REST reads')

    invalid_code = 'ZZZZZZ' if order['pickupCode'] != 'ZZZZZZ' else 'YYYYYY'
    kitchen.request('POST', '/orders/' + oid + '/complete',
                    {'expectedVersion': current['version'], 'method': 'manual', 'code': invalid_code},
                    expected=422)
    delivery_body = {'expectedVersion': current['version'], 'method': 'manual', 'code': order['pickupCode']}
    current = kitchen.request('POST', '/orders/' + oid + '/complete', delivery_body)
    kitchen.request('POST', '/orders/' + oid + '/complete', delivery_body, expected=409)
    assert current['status'] == 'completed'
    visible = student.request('GET', '/orders/' + oid)
    assert visible['status'].lower() == 'completed'
    assert not any(o['id'] == order['id'] for o in kitchen.all('/businesses/' + business_id + '/orders/active'))
    checks.append('Invalid code rejected; correct delivery succeeds once and leaves active Kitchen orders')

    rating_body = {'rating': 4, 'foodRating': 4, 'serviceRating': 5, 'comment': marker + ' negocio'}
    rating = student.request('POST', '/orders/' + oid + '/rating', rating_body, expected=201)
    student.request('POST', '/orders/' + oid + '/rating', rating_body, expected=409)
    reviews = admin.all('/admin/reviews')
    review = next(r for r in reviews if r['id'] == rating['id'])
    assert review['rating'] == 4 and review['comment'] == marker + ' negocio'
    assert not {'email', 'userId', 'orderId', 'numeroDeControl'} & review.keys()
    checks.append('Business rating appears in Administration without private student identifiers; duplicate rejected')

    product_body = {'reviews': [{'productId': product['id'], 'rating': 2, 'comment': marker + ' producto'}]}
    product_reviews = student.request('POST', '/orders/' + oid + '/reviews', product_body, expected=201)
    student.request('POST', '/orders/' + oid + '/reviews', product_body, expected=409)
    product_review = next(r for r in student.all('/products/' + pid + '/reviews')
                          if r['id'] == product_reviews['data'][0]['id'])
    assert product_review['rating'] == 2 and product_review['comment'] == marker + ' producto'
    assert not {'email', 'userId', 'orderId', 'numeroDeControl'} & product_review.keys()
    review_after = next(r for r in admin.all('/admin/reviews') if r['id'] == rating['id'])
    assert review_after['rating'] == 4 and review_after['comment'] == marker + ' negocio'
    checks.append('Product review stays separate from business rating; duplicate and identity exposure checks pass')

    followup = admin.request('PUT', '/admin/reviews/' + quote(rating['id'], safe='') + '/followup',
                            {'expectedVersion': 0, 'status': 'in_review', 'assignee': 'Prueba integrada',
                             'note': marker + ' seguimiento'})
    assert followup['status'] == 'in_review'
    checks.append('Administration can register followup on the student business rating')
    report['passed'] = True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--origin', default='http://localhost:18080')
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    origin = args.origin.rstrip('/')
    parsed = urlsplit(origin)
    if (parsed.scheme != 'http' or parsed.hostname != 'localhost' or parsed.port != 18080
            or parsed.path or parsed.query or parsed.fragment or parsed.username):
        parser.error('Only the isolated http://localhost:18080 installation is allowed')
    report = {'passed': False, 'checks': [], 'origin': origin,
              'startedAt': datetime.now(timezone.utc).isoformat(),
              'scope': 'HTTP integration of canonical students and legacy panels; no browser, load or production certification'}
    try:
        run(origin, report)
    except Exception as error:
        report['error'] = str(error) if isinstance(error, AssertionError) else type(error).__name__
    report['finishedAt'] = datetime.now(timezone.utc).isoformat()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
