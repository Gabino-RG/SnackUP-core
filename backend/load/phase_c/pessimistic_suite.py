"""Real HTTP/TLS/SQL load suite for the isolated, combined 2 CPU / 2 GiB stack.

This is a capacity experiment, not an assertion that every application endpoint
is covered. Failed stages remain failed and do not suppress subsequent stages.
Fixtures and authentication tokens stay outside the repository and reports.
"""
import argparse
import asyncio
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import re
import secrets
import time
from uuid import uuid4
from zoneinfo import ZoneInfo

import aiohttp
import socketio
from sqlalchemy import text

from . import runner

SCENARIOS = ('smoke', 'finite', 'idempotency', 'logins', 'reads', 'writes', 'burst', 'realtime', 'mixed')
READ_COUNTS = (50, 100, 300, 500, 1000)
WRITE_RATES = (1, 2, 4, 8)
RAMP_SECONDS = 15
STEADY_SECONDS = 90
REALTIME_SECONDS = 300
MIXED_SECONDS = 600


@dataclass
class Response:
    status: int
    body: dict
    raw: str
    headers: dict = field(default_factory=dict)

    def tuple(self):
        return self.status, self.body, self.raw


def automatic_retry_delay(response, jitter):
    """The shipped client retries SERVICE_BUSY once, only with a short delay."""
    error = response.body.get('error', {}) if isinstance(response.body, dict) else {}
    value = response.headers.get('retry-after', '')
    if response.status != 503 or not isinstance(error, dict) or error.get('code') != 'SERVICE_BUSY':
        return None
    if not re.fullmatch(r'\d+', str(value)) or not 0 <= int(value) <= 5:
        return None
    return int(value) + jitter


async def attempt_once_with_retry(send, jitter, sleep=asyncio.sleep):
    """Keep the initial response; recovery never rewrites first-attempt success."""
    first = await send('first')
    delay = automatic_retry_delay(first, jitter())
    if delay is None:
        return first, None, first
    await sleep(delay)
    retry = await send('automatic_retry')
    return first, retry, retry


def response_evidence(rows):
    """All attempts count, including errors; retain identity checks, not bodies."""
    successful = [row for row in rows if row.status == 201]
    return {'attempts': len(rows), 'status': dict(Counter(row.status for row in rows)),
            'successfulBodies': len({row.raw for row in successful}),
            'successfulOrderIds': len({row.body.get('id') for row in successful})}


def memory_bytes(value):
    raw = value.split('/')[0].strip()
    for unit, factor in [('GiB', 2**30), ('MiB', 2**20), ('KiB', 2**10),
                         ('GB', 10**9), ('MB', 10**6), ('kB', 1000), ('B', 1)]:
        if raw.endswith(unit):
            return float(raw[:-len(unit)]) * factor
    raise ValueError('Unknown Docker memory unit')


def configure_file_limit(resource_module):
    soft, hard = resource_module.getrlimit(resource_module.RLIMIT_NOFILE)
    unlimited = resource_module.RLIM_INFINITY
    if hard != unlimited and hard < 4096:
        raise ValueError('Generator hard file limit must be at least 4096')
    wanted = 8192 if soft == unlimited else max(soft, 8192)
    target = wanted if hard == unlimited else min(wanted, hard)
    resource_module.setrlimit(resource_module.RLIMIT_NOFILE, (target, hard))
    return {'soft': target, 'hard': hard, 'minimumRequired': 4096}


async def execute_all(names, execute):
    """A failed or exceptional scenario cannot silently truncate the matrix."""
    results = []
    for name in names:
        try:
            result = await execute(name)
        except Exception as error:
            result = {'scenario': name, 'success': False, 'failureType': type(error).__name__}
        results.append(result)
    return results


class PessimisticRun(runner.Run):
    def __init__(self, args):
        super().__init__(args)
        self.coverage = Counter()
        self.created_orders = {}
        self.hook_tasks = []
        self.probe = None
        self.admin = self.fixtures.get('administrator')
        self.student_emails = {row['email'] for row in self.students}
        self.operator_emails = {row['email'] for row in self.operators}

    def add_admin_fixture(self):
        # Run.__init__ already enforces test, ALLOW_LOAD, exact database and loopback.
        path = Path(self.args.fixtures).resolve()
        if path.is_relative_to(Path(__file__).resolve().parents[3]):
            raise ValueError('Private fixtures must remain outside the repository')
        if not self.admin:
            from snackup.auth import hash_password
            self.admin = {'email': 'admin-' + uuid4().hex + '@load.snackup.invalid',
                          'password': secrets.token_urlsafe(24)}
            with self.engine.begin() as db:
                db.execute(text('''INSERT INTO users
                    (id,email,display_name,password_hash,role,business_id,is_active,is_master,
                     approval_status,email_verified,version,auth_version,created_at,updated_at)
                    VALUES (:id,:email,'[CARGA] Administrador',:password,'admin',NULL,true,true,
                            'approved',true,1,1,now(),now())'''),
                    {'id': str(uuid4()), 'email': self.admin['email'],
                     'password': hash_password(self.admin['password'])})
            self.fixtures['administrator'] = self.admin
            path.write_text(json.dumps(self.fixtures), encoding='utf-8')
            path.chmod(0o600)
        self.accounts.append(self.admin)

    def role(self, who):
        if who is None:
            return 'anonymous'
        if who['email'] in self.student_emails:
            return 'student'
        if who['email'] in self.operator_emails:
            return 'kitchen'
        return 'administrator'

    async def request_full(self, method, path, who=None, name=None, **kwargs):
        headers = dict(kwargs.pop('headers', {}))
        if who is not None:
            await self.auth(who)
            headers['Authorization'] = 'Bearer ' + self.sessions[who['email']]['accessToken']
        start = time.perf_counter()
        try:
            async with self.http.request(method, runner.BASE + path, headers=headers, **kwargs) as response:
                raw = await response.text()
                try:
                    body = json.loads(raw)
                except ValueError:
                    body = {}
                result = Response(response.status, body, raw, {k.lower(): v for k, v in response.headers.items()})
        except (aiohttp.ClientError, TimeoutError):
            result = Response(0, {}, '')
        # Path IDs are deliberately excluded from coverage and reports.
        template = re.sub(r'/[0-9a-f-]{32,36}(?=/|$)', '/{id}', path.split('?')[0])
        self.coverage[(self.role(who), method, template, result.status)] += 1
        if name:
            self.samples[name].append((time.perf_counter() - start) * 1000)
            self.statuses[name][result.status] += 1
        if (self.probe and method == 'POST' and path.endswith('/complete') and result.status == 200
                and result.body.get('id') in self.created_orders):
            state = self.created_orders[result.body['id']]
            self.hook_tasks.append(asyncio.create_task(self.probe.on_order_delivered(state['student'], result.body, who)))
        return result

    async def request(self, method, path, who=None, name=None, **kwargs):
        return (await self.request_full(method, path, who, name, **kwargs)).tuple()

    async def purchase(self, who, business=None, product=None, key=None, metric='create'):
        result = await super().purchase(who, business, product, key, metric)
        if result[0] == 201 and result[1]['id'] not in self.created_orders:
            order = result[1]
            self.created_orders[order['id']] = {'student': who, 'order': order}
            operator = next(op for op in self.operators if op['businessId'] == order['businessId'])
            if self.probe:
                self.hook_tasks.append(asyncio.create_task(self.probe.on_order_created(who, order, operator)))
        return result

    async def stage(self, name, action):
        started, failures = time.monotonic(), len(self.failures)
        print(json.dumps({'stage': name, 'phase': 'starting'}), flush=True)
        try:
            await action()
        except Exception as error:
            self.failures.append(name + ' execution: ' + type(error).__name__)
        finally:
            self.details.setdefault('stages', []).append({'name': name,
                'elapsedSeconds': time.monotonic() - started, 'success': len(self.failures) == failures})
            print(json.dumps({'phase': 'finished', **self.details['stages'][-1]}), flush=True)

    async def drain_outbox(self, seconds=60):
        deadline = time.monotonic() + seconds
        pending = None
        while time.monotonic() < deadline:
            with self.engine.connect() as db:
                pending = db.scalar(text('SELECT count(*) FROM outbox_events WHERE published_at IS NULL'))
            if not pending:
                break
            await asyncio.sleep(1)
        self.check(pending == 0, 'Outbox did not drain within budget')
        return pending

    async def cancel_confirmed(self, orders, metric='cleanup_cancel'):
        """A paced, explicit cleanup; it never changes the measured capacity result."""
        slots = asyncio.Semaphore(4)
        async def one(who, order):
            async with slots:
                for attempt in range(3):
                    result = await self.request_full('POST', f"/api/v1/orders/{order['id']}/cancel", who, metric,
                        json={'reason': 'user_other', 'notes': '[CARGA AISLADA] Liberar reserva.', 'expectedVersion': order['version']})
                    if result.status == 200:
                        return True
                    # A timeout may have committed: read the real state before another mutation.
                    status, current, _ = await self.request('GET', f"/api/v1/orders/{order['id']}", who, metric + '_verify')
                    if status == 200:
                        if current.get('status') == 'cancelled':
                            return True
                        order = current
                    await asyncio.sleep(1 + attempt)
                self.check(False, metric + ' unconfirmed cancellation')
                return False
        results = await asyncio.gather(*(one(who, order) for who, order in orders))
        self.details.setdefault('cleanup', []).append({'intended': len(orders), 'confirmed': sum(results),
                                                       'maximumAttempts': 3, 'concurrency': 4})
        with self.engine.connect() as db:
            outstanding = db.scalar(text('SELECT count(*) FROM orders WHERE NOT stock_restored'))
            mismatched = db.scalar(text('SELECT count(*) FROM products WHERE stock <> :stock'), {'stock': self.initial_stock})
        self.check(outstanding == 0 and mismatched == 0, metric + ' stock not restored')

    async def finite(self):
        self.reset(50)
        target = self.students[0]
        rows = await asyncio.gather(*(self.purchase(who, target['businessId'], target['productId']) for who in self.students[:200]))
        codes = Counter(row[0] for row in rows)
        before = self.integrity()
        self.details['finite'] = {'attempts': 200, 'status': dict(codes), 'sold': codes[201],
            'capacityRejected503': codes[503], 'inventoryRejected422': codes[422],
            'noOversell': codes[201] <= 50 and before['negativeStock'] == 0,
            'exactSalesTarget': codes[201] == 50, 'integrityBeforeCancellation': before}
        self.check(codes == {201: 50, 422: 150}, 'Finite capacity: expected 50 sales and 150 inventory rejections')
        await self.cancel_confirmed([(who, row[1]) for who, row in zip(self.students[:200], rows) if row[0] == 201])

    async def idempotency(self):
        target = self.students[0]
        confirmed = []
        evidence = []
        async def group(who):
            key = str(uuid4())
            rows = await asyncio.gather(*(self.purchase(who, target['businessId'], target['productId'], key) for _ in range(10)))
            data = response_evidence([Response(*row) for row in rows])
            evidence.append(data)
            self.check(data['successfulBodies'] == data['successfulOrderIds'] == 1, 'Idempotency missing or different successful body/ID')
            self.check(all(row[0] in (201, 503) for row in rows), 'Idempotency unexpected response')
            # Same key/body replay is verification, explicitly outside the 500 submissions.
            verified = await self.purchase(who, target['businessId'], target['productId'], key, 'idempotency_verify')
            self.check(verified[0] == 201, 'Idempotency verification did not resolve intent')
            originals = [row for row in rows if row[0] == 201]
            self.check(not originals or verified[2] == originals[0][2], 'Idempotency replay changed body')
            if verified[0] == 201:
                confirmed.append((who, verified[1]))
        await asyncio.gather(*(group(who) for who in self.students[:50]))
        self.details['idempotency'] = {'groups': evidence, 'initialSubmissions': sum(row['attempts'] for row in evidence),
                                      'confirmedIntentsAfterVerification': len(confirmed)}
        self.check(self.integrity()['orders'] == 50, 'Idempotency SQL expected 50 unique orders')
        await self.cancel_confirmed(confirmed)

    async def reads(self):
        for count in READ_COUNTS:
            async def one(count=count):
                metric = f'read_{count}'
                start = time.monotonic() - self.started
                await self.read_users(count, RAMP_SECONDS + STEADY_SECONDS, metric, RAMP_SECONDS)
                self.details.setdefault('readingStages', []).append({'users': count, 'start': start + RAMP_SECONDS,
                    'end': start + RAMP_SECONDS + STEADY_SECONDS, 'rampSeconds': RAMP_SECONDS, 'steadySeconds': STEADY_SECONDS})
                self.check((runner.quantile(self.samples[metric], .95) or math.inf) < 750, metric + ' steady p95 >=750ms')
                self.check((runner.quantile(self.samples[metric], .99) or math.inf) < 2000, metric + ' steady p99 >=2000ms')
            await self.stage('reads_' + str(count), one)
            await asyncio.sleep(5)

    async def writes(self):
        for rate in WRITE_RATES:
            async def one(rate=rate):
                metric = f'create_{rate}'
                accepted = []
                async def create(index):
                    who = self.students[index % 1000]
                    result = await self.purchase(who, metric=metric)
                    self.check(result[0] == 201, metric + ' initial creation failed')
                    if result[0] == 201:
                        accepted.append((who, result[1]))
                        # Actual user think time; cancellation is not back-to-back with creation.
                        await asyncio.sleep(self.random.uniform(2, 5))
                        status, _, _ = await self.cancel(who, result[1])
                        self.check(status == 200, metric + ' initial cancellation failed')
                await self.arrival(rate, STEADY_SECONDS, create)
                self.check((runner.quantile(self.samples[metric], .95) or math.inf) < 1500, metric + ' p95 >=1500ms')
                await self.cancel_confirmed(accepted, metric + '_cleanup')
            await self.stage('writes_' + str(rate), one)
            await asyncio.sleep(10)

    async def burst(self):
        intents = []
        for who in self.students:
            intents.append({'student': who, 'key': str(uuid4()), 'body': {
                'businessId': who['businessId'], 'items': [{'productId': who['productId'], 'quantity': 1}],
                'paymentMethod': 'Efectivo', 'expectedTotal': 10.0}})
        async def send(intent, phase):
            return await self.request_full('POST', '/api/v1/orders', intent['student'], 'burst_' + phase,
                json=intent['body'], headers={'Idempotency-Key': intent['key']})
        async def one(intent):
            start = time.monotonic()
            first, retry, final = await attempt_once_with_retry(lambda phase: send(intent, phase),
                lambda: self.random.uniform(0, 1.499))
            intent.update(first=first, retry=retry, final=final)
            self.samples['burst_automatic_intent'].append((time.monotonic() - start) * 1000)
        await asyncio.gather(*(one(intent) for intent in intents))
        unresolved = [intent for intent in intents if intent['final'].status != 201]
        evidence = {'intents': 1000, 'firstAttempt': response_evidence([i['first'] for i in intents]),
            'automaticRetry': response_evidence([i['retry'] for i in intents if i['retry'] is not None]),
            'confirmedAfterAutomaticPolicy': 1000 - len(unresolved), 'unconfirmedBeforeManualRecovery': len(unresolved),
            'automaticRetryLimit': 1, 'retryAfterMaximumSeconds': 5, 'jitterMaximumSeconds': 1.499}
        self.check(sum(i['first'].status != 201 for i in intents) < 10, 'Burst first-attempt error rate >=1%')
        self.check((runner.quantile(self.samples['burst_first'], .95) or math.inf) < 1500, 'Burst first-attempt p95 >=1500ms')
        self.check(not unresolved, 'Burst capacity: unconfirmed intents after the single automatic retry')
        # Manual user recovery is a separate, rate-limited stage using the SAME key and body.
        recovery_deadline = time.monotonic() + 300
        for round_index, rate in enumerate((5, 2, 1)):
            if not unresolved:
                break
            capacity = max(0, int((recovery_deadline - time.monotonic()) * rate))
            pending, untouched = unresolved[:capacity], unresolved[capacity:]
            if not pending:
                break
            async def recover(index):
                intent = pending[index]
                intent['final'] = await send(intent, 'manual_recovery')
            await self.arrival(rate, len(pending) / rate, recover)
            unresolved = [intent for intent in pending if intent['final'].status != 201] + untouched
            evidence.setdefault('manualRecoveryRounds', []).append({'round': round_index + 1, 'rate': rate,
                'attempts': len(pending), 'remainingUnconfirmed': len(unresolved)})
            if unresolved:
                await asyncio.sleep(3)
        evidence['unresolvedAfterManualRecovery'] = len(unresolved)
        evidence['manualRecoveryBudgetSeconds'] = 300
        confirmed = [intent for intent in intents if intent['final'].status == 201]
        evidence['confirmedIncludingManual'] = len(confirmed)
        evidence['uniqueConfirmedOrderIds'] = len({intent['final'].body.get('id') for intent in confirmed})
        with self.engine.connect() as db:
            evidence['sqlOrdersBeforeCancellation'] = db.scalar(text('SELECT count(*) FROM orders'))
        self.check(not unresolved and evidence['sqlOrdersBeforeCancellation'] == evidence['uniqueConfirmedOrderIds'] == 1000,
                   'Burst unresolved intentions, duplicate returned IDs or SQL count mismatch')
        self.details['burst'] = evidence
        await self.cancel_confirmed([(i['student'], i['final'].body) for i in confirmed], 'burst_cleanup')

    async def administration(self, seconds):
        deadline = time.monotonic() + seconds
        day = datetime.now(ZoneInfo('America/Mexico_City')).date().isoformat()
        cycle = 0
        while time.monotonic() < deadline:
            paths = [('/api/v1/admin/businesses?limit=20', 'admin_businesses', self.admin),
                     ('/api/v1/admin/users?limit=20', 'admin_users', self.admin),
                     ('/api/v1/admin/reviews?limit=20', 'admin_reviews', self.admin)]
            paths.extend((f"/api/v1/businesses/{op['businessId']}/stats?from={day}&to={day}", 'kitchen_stats', op) for op in self.operators)
            for path, metric, actor in paths:
                status, _, _ = await self.request('GET', path, actor, metric)
                self.check(status == 200, metric + ' HTTP failure')
            cycle += 1
            await asyncio.sleep(min(10, max(0, deadline - time.monotonic())))
        self.details['administration'] = {'cycles': cycle, 'plannedSeconds': seconds,
            'requests': {name: sum(self.statuses[name].values()) for name in ('admin_businesses', 'admin_users', 'admin_reviews', 'kitchen_stats')}}
        for name in ('admin_businesses', 'admin_users', 'admin_reviews', 'kitchen_stats'):
            self.check(self.statuses[name][200] > 0, name + ' no successful activity')

    async def mixed(self):
        from .collaboration_probe import Probe
        self.probe = Probe(self)
        clients, disconnected, subscribed = [], [], set()
        product_deliveries, order_deliveries = Counter(), Counter()
        slots = asyncio.Semaphore(25)
        async def connect(index, who):
            async with slots:
                try:
                    await self.auth(who, MIXED_SECONDS + 600)
                    sio = socketio.AsyncClient(http_session=self.http, reconnection=False, logger=False, engineio_logger=False)
                    async def product(event):
                        data = event['data']
                        product_deliveries[(index, event['id'], data.get('businessId'))] += 1
                        self.samples['mixed_product_event'].append((time.time() - datetime.fromisoformat(event['occurredAt']).timestamp()) * 1000)
                    async def order(event):
                        data = event['data']
                        order_deliveries[(index, data['id'], data['version'])] += 1
                        self.received_order_events.add((data['id'], data['version']))
                        self.samples['mixed_order_event'].append((time.time() - datetime.fromisoformat(event['occurredAt']).timestamp()) * 1000)
                    async def disconnect(*_):
                        disconnected.append(index)
                    sio.on('product.updated', product)
                    sio.on('order.updated', order)
                    sio.on('order.created', order)
                    sio.on('disconnect', disconnect)
                    await sio.connect(runner.BASE, transports=['websocket'], auth={'token': self.sessions[who['email']]['accessToken']},
                                      headers={'Origin': runner.BASE}, wait_timeout=30)
                    clients.append(sio)
                    status, me, _ = await self.request('GET', '/api/v1/users/me', who, 'mixed_subscriber_identity')
                    if status != 200:
                        raise RuntimeError('Subscriber identity unavailable')
                    ack = await sio.call('subscribe', {'topics': [f"business:{who['businessId']}:products", f"user:{me['id']}:orders"]}, timeout=30)
                    self.check(ack.get('ok'), 'Mixed subscription denied')
                    if ack.get('ok'):
                        subscribed.add(index)
                except Exception as error:
                    self.check(False, 'Mixed connection: ' + type(error).__name__)
        try:
            await asyncio.gather(*(connect(index, who) for index, who in enumerate(self.students)))
            self.details['mixedConnections'] = len(clients)
            self.details['mixedConfirmedSubscriptions'] = len(subscribed)
            self.check(len(clients) == 1000, 'Mixed did not connect 1000 WebSockets')
            self.check(len(subscribed) == 1000, 'Mixed did not confirm 1000 subscriptions')
            started = time.monotonic()
            results = await asyncio.gather(self.read_users(1000, MIXED_SECONDS, 'mixed_read'),
                self.kitchen(1.5, MIXED_SECONDS), self.administration(MIXED_SECONDS), return_exceptions=True)
            for result in results:
                if isinstance(result, BaseException):
                    self.check(False, 'Mixed task failed: ' + type(result).__name__)
            if self.hook_tasks:
                hooks = await asyncio.gather(*self.hook_tasks, return_exceptions=True)
                for result in hooks:
                    if isinstance(result, BaseException):
                        self.check(False, 'Collaboration callback failed: ' + type(result).__name__)
            await self.probe.finish()
            await self.drain_outbox()
            await asyncio.sleep(3)
            index_by_email = {who['email']: index for index, who in enumerate(self.students)}
            expected = {(index_by_email[self.created_orders[oid]['student']['email']], oid, version)
                        for oid, version in self.expected_order_events if oid in self.created_orders}
            received = set(order_deliveries)
            # The authoritative outbox is the oracle: equal totals alone could
            # hide a missing delivery balanced by an unexpected event/version.
            with self.engine.connect() as db:
                publications = list(db.execute(text("SELECT event_id,data FROM outbox_events WHERE event_type='product.updated'")).mappings())
            expected_products = set()
            for publication in publications:
                data = publication['data']
                if isinstance(data, str):
                    data = json.loads(data)
                for index, student in enumerate(self.students):
                    if student['businessId'] == data.get('businessId'):
                        expected_products.add((index, publication['event_id'], data['businessId']))
            wrong_business = sum(count for (index, _, business), count in product_deliveries.items()
                                 if self.students[index]['businessId'] != business)
            self.details['mixed'] = {'steadySeconds': MIXED_SECONDS, 'elapsedIncludingDrainSeconds': time.monotonic() - started,
                'expectedOrderDeliveries': len(expected), 'receivedOrderDeliveries': len(received),
                'missingOrderDeliveries': len(expected - received), 'unexpectedOrderDeliveries': len(received - expected),
                'duplicateOrderDeliveries': sum(value - 1 for value in order_deliveries.values()),
                'productPublications': len(publications),
                'expectedProductDeliveries': len(expected_products), 'receivedProductDeliveries': len(product_deliveries),
                'missingProductDeliveries': len(expected_products - set(product_deliveries)),
                'unexpectedProductDeliveries': len(set(product_deliveries) - expected_products),
                'duplicateProductDeliveries': sum(value - 1 for value in product_deliveries.values()),
                'wrongBusinessDeliveries': wrong_business, 'unexpectedDisconnects': len(disconnected)}
            self.check(bool(expected) and received == expected, 'Mixed order event delivery mismatch')
            self.check(len(publications) == len(self.created_orders), 'Mixed stock publications differ from confirmed purchases')
            self.check(set(product_deliveries) == expected_products and not wrong_business, 'Mixed stock event delivery mismatch')
            self.check(all(value == 1 for value in product_deliveries.values()), 'Mixed duplicate stock events')
            self.check(all(value == 1 for value in order_deliveries.values()), 'Mixed duplicate order events')
            self.check(not disconnected, 'Mixed unexpected WebSocket disconnect')
            for metric in ('mixed_order_event', 'mixed_product_event'):
                self.check((runner.quantile(self.samples[metric], .95) or math.inf) < 2000, metric + ' p95 >=2000ms')
            self.check((runner.quantile(self.samples['mixed_read'], .95) or math.inf) < 750, 'Mixed read p95 >=750ms')
            self.check(self.statuses['kitchen_transition'][200] > 0, 'Mixed kitchen had no successful transitions')
        finally:
            await asyncio.gather(*(client.disconnect() for client in clients), return_exceptions=True)

    def resource_summary(self):
        by_pid = defaultdict(list)
        for sample in self.worker_samples:
            self.check(len(sample['workers']) == 1, 'Expected exactly one API worker')
            for row in sample['workers']:
                by_pid[row['pid']].append((sample['time'], row['cpuSeconds'], row['rssBytes']))
        workers = [{'pid': pid, 'peakRssMiB': max(row[2] for row in rows) / 2**20,
            'meanCpuPercent': (rows[-1][1] - rows[0][1]) / max(.001, rows[-1][0] - rows[0][0]) * 100}
            for pid, rows in by_pid.items()]
        peak = max((sum(memory_bytes(container['MemUsage']) for container in sample['containers'])
                    for sample in self.monitor), default=0) / 2**20
        self.check(bool(workers) and bool(self.monitor), 'Resource monitoring unavailable')
        self.check(peak <= 2048, 'Combined service memory exceeds 2048 MiB')
        self.check(len(workers) == 1, 'API worker restarted or monitoring saw multiple workers')
        if self.args.scenario == 'logins':
            self.check(all(worker['peakRssMiB'] < 400 for worker in workers), 'Login worker RSS >=400 MiB')
        cpu = [(sample['elapsed'], sum(float(row['CPUPerc'].rstrip('%')) for row in sample['containers']) / 2)
               for sample in self.monitor]
        stages = []
        for stage in self.details.get('readingStages', []):
            values = [value for elapsed, value in cpu if stage['start'] <= elapsed <= stage['end']]
            cpu_pass = bool(values) and sum(values) / len(values) < 75
            self.check(cpu_pass, f"Read {stage['users']} steady CPU >=75% or unavailable")
            for measured in self.details.get('stages', []):
                if measured['name'] == 'reads_' + str(stage['users']):
                    measured['cpuCriterionPassed'] = cpu_pass
                    measured['success'] = measured['success'] and cpu_pass
            stages.append({**stage, 'meanTwoCpuUtilizationPercent': sum(values) / len(values) if values else None,
                           'p95TwoCpuUtilizationPercent': runner.quantile(values, .95), 'cpuCriterionPassed': cpu_pass})
        return {'budgetMiB': 2048, 'sharedCpuCount': 2, 'workers': workers, 'peakContainersMiB': peak,
                'readingStages': stages, 'workerBalanceCriterion': 'not applicable: one worker'}

    async def run_case(self):
        self.started = time.monotonic()
        print(json.dumps({'scenario': self.args.scenario, 'phase': 'starting'}), flush=True)
        monitors = []
        reset_done = False
        try:
            async with aiohttp.ClientSession(connector=aiohttp.TCPConnector(limit=2400, ssl=self.tls_context or True),
                cookie_jar=aiohttp.DummyCookieJar(), timeout=aiohttp.ClientTimeout(total=15)) as self.http:
                self.add_admin_fixture()
                await self.prepare()
                self.reset()
                reset_done = True
                self.details['preparation'] = {'accounts': len(self.accounts), 'authenticationConcurrency': 8,
                                               'excludedFromMeasuredScenarios': True}
                monitors = [asyncio.create_task(self.resources()), asyncio.create_task(self.worker_resources())]
                try:
                    if self.args.scenario == 'smoke':
                        await self.p0()
                    elif self.args.scenario == 'logins':
                        await self.p7b()
                    elif self.args.scenario == 'realtime':
                        await self.realtime(1000, REALTIME_SECONDS)
                    else:
                        await getattr(self, self.args.scenario)()
                finally:
                    await self.drain_outbox()
                    self.details['integrity'] = self.integrity()
        except Exception as error:
            self.failures.append('Scenario execution: ' + type(error).__name__)
            self.details['resetCompleted'] = reset_done
        finally:
            self.running = False
            for task in monitors:
                task.cancel()
            await asyncio.gather(*monitors, return_exceptions=True)
            try:
                self.details['resources'] = self.resource_summary()
            except Exception as error:
                self.failures.append('Resource summary: ' + type(error).__name__)
            for name, codes in self.statuses.items():
                self.check(codes[500] == codes[0] == 0, name + ' internal/transport errors')
            self.auth_path.write_text(json.dumps(self.sessions), encoding='utf-8')
            self.auth_path.chmod(0o600)
            metrics = {name: {'count': len(values), 'p50Ms': runner.quantile(values, .5),
                'p95Ms': runner.quantile(values, .95), 'p99Ms': runner.quantile(values, .99),
                'status': dict(self.statuses[name])} for name, values in self.samples.items()}
            report = {'scenario': self.args.scenario, 'profile': '2cpu-2gib-total', 'quick': False,
                'commit': os.environ.get('GITHUB_SHA'), 'elapsedSeconds': time.monotonic() - self.started,
                'success': not self.failures, 'failures': dict(Counter(self.failures)), 'details': self.details,
                'metrics': metrics, 'resources': self.monitor, 'transport': self.transport,
                'coverage': [{'role': role, 'method': method, 'path': path, 'status': status, 'count': count}
                             for (role, method, path, status), count in sorted(self.coverage.items())]}
            Path(self.args.output).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
            self.engine.dispose()
            print(json.dumps({key: report[key] for key in ('scenario', 'success', 'elapsedSeconds', 'failures')}), flush=True)
        return report


async def run_suite(args):
    from .verify_pessimistic_limits import sample_limits, validate_history
    output = Path(args.output_dir)
    output.mkdir(parents=True, exist_ok=True)
    names = SCENARIOS if args.scenario == 'all' else (args.scenario,)
    runner.BASE, context, transport = runner.load_transport()
    if context is None:
        raise ValueError('This profile requires verified HTTPS and WSS')
    compose_files = os.environ.get('SNACKUP_LOAD_COMPOSE_FILES') or os.environ.get('COMPOSE_FILE')
    if not compose_files:
        raise ValueError('Explicit Compose overlays are required for resource sampling')
    runner.COMPOSE = ['docker', 'compose']
    for filename in compose_files.split(os.pathsep):
        runner.COMPOSE.extend(['-f', filename])
    samples, stop = [], asyncio.Event()
    async def monitor_limits():
        with (output / 'resources-samples.jsonl').open('w', encoding='utf-8') as destination:
            while not stop.is_set():
                try:
                    sample = await asyncio.to_thread(sample_limits)
                except Exception as error:
                    sample = {'samplingError': type(error).__name__}
                samples.append(sample)
                destination.write(json.dumps(sample) + '\n')
                destination.flush()
                try:
                    await asyncio.wait_for(stop.wait(), timeout=5)
                except TimeoutError:
                    pass
    monitor = asyncio.create_task(monitor_limits())
    async def execute(name):
        case_args = argparse.Namespace(fixtures=args.fixtures, output=str(output / (name + '.json')),
                                       scenario=name, profile='pessimistic', quick=False)
        try:
            case = PessimisticRun(case_args)
            case.tls_context, case.transport = context, transport
            report = await case.run_case()
        except Exception as error:
            report = {'scenario': name, 'success': False, 'elapsedSeconds': 0,
                      'failures': {'Scenario initialization/reporting: ' + type(error).__name__: 1}}
            Path(case_args.output).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        return {key: report[key] for key in ('scenario', 'success', 'elapsedSeconds', 'failures')}
    try:
        results = await execute_all(names, execute)
    finally:
        stop.set()
        await monitor
    limits = validate_history(samples)
    (output / 'resources-validation.json').write_text(json.dumps(limits, indent=2) + '\n', encoding='utf-8')
    summary = {'profile': '2cpu-2gib-total', 'scenarioOrder': list(names), 'results': results,
        'resourceLimits': limits, 'success': all(row['success'] for row in results) and limits['success'],
        'scope': 'Only recorded endpoints and roles; not a claim of exhaustive UI coverage',
        'temporaryData': True, 'commit': os.environ.get('GITHUB_SHA')}
    summary['generatorFileLimits'] = getattr(args, 'file_limits', None)
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    return 0 if summary['success'] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixtures', required=True)
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--scenario', choices=('all',) + SCENARIOS, default='all')
    args = parser.parse_args()
    # Linux CI provides four CPUs: generators must not share service CPUs 0-1.
    os.sched_setaffinity(0, {2, 3})
    import resource
    args.file_limits = configure_file_limit(resource)
    return asyncio.run(run_suite(args))


if __name__ == '__main__':
    raise SystemExit(main())
