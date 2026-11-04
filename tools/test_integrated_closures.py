"""Observe the real local scheduler and preserve demonstration availability.

Only integration-local at http://localhost:18080 may be changed. The automatic
closure is processed once per local calendar day; its audit marker is retained.
Run without other users operating this demonstration business. Snapshot/verify
modes permit an external supervisor to restart the server between invocations;
this script never stops a server and never serializes credentials or tokens.
"""
import argparse
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import time
from urllib.parse import quote
from uuid import uuid4
from zoneinfo import ZoneInfo

from test_integrated_flow import Client

ORIGIN = 'http://localhost:18080'
BUSINESS = 'integration-local'
BUSINESS_PATH = '/businesses/' + BUSINESS


def sessions():
    student = Client(ORIGIN, '/api/v1')
    kitchen = Client(ORIGIN, '/api/legacy/v1')
    admin = Client(ORIGIN, '/api/legacy/v1')
    student.login('alumno.demo@utsjr.edu.mx')
    kitchen.login('operator@staff.example.edu')
    admin.login('master@staff.example.edu')
    canonical = Client(ORIGIN, '/api/v1')
    canonical.token = kitchen.token
    return student, kitchen, admin, canonical


def health():
    value = Client(ORIGIN, '').request('GET', '/health/integration')
    assert value['scheduler'] is True and value['status'] == 'ready', 'Scheduler is not healthy'


def visible_to_all(clients, is_open):
    student, kitchen, admin = clients
    for client in (student, kitchen):
        business = client.request('GET', BUSINESS_PATH)
        assert business['isOpen'] is is_open, 'Availability differs between student, Kitchen and Administration'
    business = next(item for item in admin.all('/admin/businesses') if item['id'] == BUSINESS)
    assert business['isOpen'] is is_open, 'Administration does not see the authoritative availability'


def reconnect(client):
    """Create a fresh HTTP transport without changing the authenticated identity."""
    fresh = Client(client.origin, client.prefix)
    fresh.token = client.token
    return fresh


def durable_state(student, canonical, admin):
    business = canonical.request('GET', BUSINESS_PATH)
    fields = ('id', 'isOpen', 'isActive', 'timezone', 'version', 'autoCloseEnabled',
              'closeTimeLocal', 'postponedCloseAt', 'lastAutoCloseDate')
    product_fields = ('id', 'stock', 'version', 'isAvailable', 'price')
    order_fields = ('id', 'status', 'version', 'total')
    orders = student.all('/users/me/orders/history') + student.all('/users/me/orders/active')
    return {
        'business': {field: business[field] for field in fields},
        'products': sorted(({field: item[field] for field in product_fields}
                            for item in student.all(BUSINESS_PATH + '/products')), key=lambda x: x['id']),
        'orders': sorted(({field: item[field] for field in order_fields}
                          for item in orders if item['businessId'] == BUSINESS), key=lambda x: x['id']),
        'reviews': sorted(({'id': item['id'], 'rating': item['rating']}
                           for item in admin.all('/admin/reviews') if item['businessId'] == BUSINESS),
                          key=lambda x: x['id']),
    }


def closure_test(report, clients):
    student, kitchen, admin, canonical = clients
    checks = report['checks']
    original = canonical.request('GET', BUSINESS_PATH)
    zone = ZoneInfo(original['timezone'])
    now = datetime.now(zone)
    assert original['isActive'], 'The demonstration business is inactive'
    assert original['postponedCloseAt'] is None, 'Do not overwrite an existing postponement'
    assert original['lastAutoCloseDate'] != now.date().isoformat(), (
        'Automatic closure already processed today; rerun on another day without resetting its history')
    assert not kitchen.all(BUSINESS_PATH + '/orders/active'), (
        'Finish the demonstration business active orders before this isolated closure test')
    products = student.all(BUSINESS_PATH + '/products')
    product = next((item for item in products if item['isAvailable'] and
                    (item['stock'] is None or item['stock'] > 0)), None)
    assert product, 'No available demonstration product'
    deadline = now.replace(second=0, microsecond=0) + timedelta(minutes=1)
    if (deadline - now).total_seconds() < 15:
        deadline += timedelta(minutes=1)
    assert deadline.date() == now.date(), 'Run this test away from local midnight'
    report['scheduledFor'] = deadline.isoformat()
    changed = False
    try:
        current = canonical.request('PATCH', BUSINESS_PATH + '/closing-schedule', {
            'expectedVersion': original['version'], 'autoCloseEnabled': True,
            'closeTimeLocal': deadline.strftime('%H:%M')})
        changed = True
        if not current['isOpen']:
            current = kitchen.request('PATCH', BUSINESS_PATH + '/status', {
                'expectedVersion': current['version'], 'isOpen': True})
        visible_to_all((student, kitchen, admin), True)
        checks.append('Scheduled a future closure while all three roles see the business open')
        print('Waiting for the real scheduler to close integration-local...', flush=True)
        timeout = time.monotonic() + (deadline - datetime.now(zone)).total_seconds() + 25
        while time.monotonic() < timeout:
            current = canonical.request('GET', BUSINESS_PATH)
            if not current['isOpen']:
                break
            time.sleep(2)
        assert not current['isOpen'], 'Scheduler did not close the business before the deadline tolerance'
        assert current['lastAutoCloseDate'] == deadline.date().isoformat(), 'Closure has no processed-date marker'
        assert datetime.now(zone) >= deadline, 'Business closed before the scheduled time'
        health()
        visible_to_all((student, kitchen, admin), False)
        checks.append('The live scheduler closed the business; Kitchen, Administration and student agree')

        pid = quote(product['id'], safe='')
        before = student.request('GET', '/products/' + pid)
        active_before = student.all('/users/me/orders/active')
        rejected = student.request('POST', '/orders', {
            'businessId': BUSINESS, 'items': [{'productId': product['id'], 'quantity': 1}],
            'paymentMethod': 'Efectivo', 'expectedTotal': product['price']},
            key=str(uuid4()), expected=409)
        assert rejected['error']['code'] == 'BUSINESS_CLOSED', 'Closed business returned an unexpected rejection'
        after = student.request('GET', '/products/' + pid)
        assert before['stock'] == after['stock'], 'Rejected purchase changed stock'
        assert student.all('/users/me/orders/active') == active_before, 'Rejected purchase created an active order'
        checks.append('Closed business rejects purchase without creating an order or reserving stock')

        # The old transports can be discarded and the identities still see the
        # authoritative state. This is not an outage/retry test of Flutter.
        visible_to_all(tuple(reconnect(client) for client in (student, kitchen, admin)), False)
        checks.append('New HTTP transports with existing access sessions recover the authoritative closed state')

        current = canonical.request('GET', BUSINESS_PATH)
        reopened = kitchen.request('PATCH', BUSINESS_PATH + '/status', {
            'expectedVersion': current['version'], 'isOpen': True})
        time.sleep(7)  # Greater than the integration launcher's five-second cycle.
        health()
        visible_to_all((student, kitchen, admin), True)
        current = canonical.request('GET', BUSINESS_PATH)
        assert current['version'] == reopened['version'], 'Scheduler changed the manually reopened business'
        checks.append('Manual reopening remains open after another scheduler cycle without a duplicate closure')
    finally:
        if changed:
            try:
                current = canonical.request('GET', BUSINESS_PATH)
                current = canonical.request('PATCH', BUSINESS_PATH + '/closing-schedule', {
                    'expectedVersion': current['version'], 'autoCloseEnabled': original['autoCloseEnabled'],
                    'closeTimeLocal': original['closeTimeLocal']})
                if current['isOpen'] != original['isOpen']:
                    kitchen.request('PATCH', BUSINESS_PATH + '/status', {
                        'expectedVersion': current['version'], 'isOpen': original['isOpen']})
                restored = canonical.request('GET', BUSINESS_PATH)
                for field in ('autoCloseEnabled', 'closeTimeLocal', 'isOpen'):
                    assert restored[field] == original[field], 'Original operating configuration was not restored'
                report['availabilityRestored'] = True
                checks.append('Original availability and schedule restored; the processed-date audit marker is retained')
            except Exception as error:
                report['availabilityRestored'] = False
                report['restoreError'] = str(error) if isinstance(error, AssertionError) else type(error).__name__
                raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=('closure', 'snapshot', 'verify'), default='closure')
    parser.add_argument('--snapshot', type=Path, help='Credential-free state before/after an externally managed restart')
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    if args.mode != 'closure' and args.snapshot is None:
        parser.error('--snapshot is required for snapshot/verify')
    report = {'passed': False, 'checks': [], 'origin': ORIGIN, 'mode': args.mode,
              'startedAt': datetime.now(timezone.utc).isoformat(),
              'scope': 'Real local scheduler and REST state; no Flutter outage UX, load or production certification'}
    try:
        health()
        clients = sessions()
        if args.mode == 'closure':
            closure_test(report, clients)
        else:
            student, kitchen, admin, canonical = clients
            state = durable_state(student, canonical, admin)
            if args.mode == 'snapshot':
                args.snapshot.parent.mkdir(parents=True, exist_ok=True)
                args.snapshot.write_text(json.dumps({'origin': ORIGIN, 'businessId': BUSINESS, 'state': state},
                                                     ensure_ascii=False, indent=2), encoding='utf-8')
                report['checks'].append('Saved credential-free availability, inventory, orders and ratings baseline')
            else:
                saved = json.loads(args.snapshot.read_text(encoding='utf-8'))
                assert saved['origin'] == ORIGIN and saved['businessId'] == BUSINESS, 'Snapshot is not from the isolated installation'
                assert saved['state'] == state, 'Persisted state differs from the saved baseline'
                visible_to_all((student, kitchen, admin), state['business']['isOpen'])
                report['checks'].append('Scheduler is healthy and all three identities authenticate on fresh connections')
                report['checks'].append('Availability, inventory, orders and ratings match the pre-restart baseline')
                report['externalRestartRequired'] = True
        report['passed'] = True
    except Exception as error:
        report['error'] = str(error) if isinstance(error, AssertionError) else type(error).__name__
    report['finishedAt'] = datetime.now(timezone.utc).isoformat()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
