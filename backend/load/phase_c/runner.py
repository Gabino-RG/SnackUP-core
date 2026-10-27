"""Documented Phase C scenarios, real HTTP/Socket.IO and SQL integrity.

Only a new disposable loadtest DB on loopback is accepted. No credentials or
response bodies enter the report. --quick explicitly reduces durations only.
"""
import argparse
import asyncio
from collections import Counter, defaultdict
from datetime import datetime
import json
import math
import os
from pathlib import Path
import random
import subprocess
import time
from uuid import uuid4

import aiohttp
import socketio
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url

BASE = 'http://127.0.0.1:18080'
COMPOSE = ['docker', 'compose', '-f', 'load/phase_c/compose.yaml']


def quantile(values, fraction):
    return sorted(values)[max(0, math.ceil(len(values) * fraction) - 1)] if values else None


class Run:
    def __init__(self, args):
        self.args = args
        self.fixtures = json.loads(Path(args.fixtures).read_text())
        self.accounts = self.fixtures['students'] + self.fixtures['operators']
        self.students = self.accounts[:1000]
        self.operators = self.accounts[1000:]
        assert len(self.students) == 1000 and len(self.operators) == 4
        url = os.environ['SNACKUP_DATABASE_URL']
        parsed = make_url(url)
        assert os.environ.get('ALLOW_LOAD') == 'YES' and os.environ.get('SNACKUP_ENVIRONMENT') == 'test'
        assert parsed.database == 'snackup_loadtest' and parsed.host in {'localhost', '127.0.0.1'}
        self.engine = create_engine(url)
        self.auth_path = Path(args.fixtures).with_suffix('.sessions.json')
        self.sessions = json.loads(self.auth_path.read_text()) if self.auth_path.exists() else {}
        self.locks = defaultdict(asyncio.Lock)
        self.samples, self.statuses = defaultdict(list), defaultdict(Counter)
        self.failures, self.details, self.monitor = [], {}, []
        self.random = random.Random(20261027)
        self.running = True

    def check(self, condition, message):
        if not condition:
            self.failures.append(message)

    async def request(self, method, path, who=None, name=None, **kwargs):
        headers = kwargs.pop('headers', {})
        if who is not None:
            await self.auth(who)
            headers['Authorization'] = 'Bearer ' + self.sessions[who['email']]['accessToken']
        start = time.perf_counter()
        try:
            async with self.http.request(method, BASE + path, headers=headers, **kwargs) as response:
                raw = await response.text()
                status = response.status
                try:
                    body = json.loads(raw)
                except ValueError:
                    body = {}
        except (aiohttp.ClientError, TimeoutError):
            status, body, raw = 0, {}, ''
        if name:
            self.samples[name].append((time.perf_counter() - start) * 1000)
            self.statuses[name][status] += 1
        return status, body, raw

    async def auth(self, who):
        async with self.locks[who['email']]:
            current = self.sessions.get(who['email'])
            if current and datetime.fromisoformat(current['accessTokenExpiresAt']).timestamp() > time.time() + 60:
                return
            if current:
                status, body, _ = await self.request('POST', '/api/v1/auth/refresh',
                    json={'refreshToken': current['refreshToken']}, name='refresh')
                if status == 200:
                    self.sessions[who['email']] = body['tokens']
                    return
            status, body, _ = await self.request('POST', '/api/v1/auth/login',
                json={'email': who['email'], 'password': who['password']})
            if status != 200:
                raise RuntimeError('Fixture authentication failed with HTTP ' + str(status))
            self.sessions[who['email']] = body['tokens']

    async def prepare(self):
        slots = asyncio.Semaphore(8)
        async def one(account):
            async with slots:
                await self.auth(account)
        await asyncio.gather(*(one(a) for a in self.accounts))
        self.auth_path.write_text(json.dumps(self.sessions))
        self.auth_path.chmod(0o600)

    def reset(self, stock=100000):
        with self.engine.begin() as db:
            db.execute(text('TRUNCATE orders, order_items, order_transitions, idempotency_records, meal_voucher_uses, '
                            'chats, chat_messages, chat_closures, outbox_events RESTART IDENTITY CASCADE'))
            db.execute(text('UPDATE businesses SET next_order_number=1, is_open=true, auto_close_enabled=false'))
            db.execute(text('UPDATE products SET stock=:stock, is_available=true, manual_available=true'), {'stock': stock})
        self.initial_stock = stock

    def integrity(self):
        with self.engine.connect() as db:
            checks = {
                'negativeStock': 'SELECT count(*) FROM products WHERE stock<0',
                'duplicateNumbers': 'SELECT count(*) FROM (SELECT business_id,order_number FROM orders GROUP BY 1,2 HAVING count(*)>1) q',
                'duplicateCodes': 'SELECT count(*) FROM (SELECT pickup_code FROM orders WHERE length(pickup_code)=6 GROUP BY 1 HAVING count(*)>1) q',
                'duplicateKeys': 'SELECT count(*) FROM (SELECT user_id,key FROM idempotency_records GROUP BY 1,2 HAVING count(*)>1) q',
                'inventoryMismatch': '''SELECT count(*) FROM products p WHERE p.stock + COALESCE((
                    SELECT sum(i.reserved_quantity) FROM order_items i JOIN orders o ON o.id=i.order_id
                    WHERE i.product_id=p.id AND NOT o.stock_restored),0) != :stock''',
            }
            result = {k: db.scalar(text(sql), {'stock': self.initial_stock}) for k, sql in checks.items()}
            result['pendingOutbox'] = db.scalar(text('SELECT count(*) FROM outbox_events WHERE published_at IS NULL'))
            result['deadlocks'] = db.scalar(text("SELECT deadlocks FROM pg_stat_database WHERE datname=current_database()"))
            result['orders'] = db.scalar(text('SELECT count(*) FROM orders'))
        for key in checks:
            self.check(result[key] == 0, key)
        self.check(result['deadlocks'] == 0, 'PostgreSQL deadlocks')
        return result

    async def purchase(self, who, business=None, product=None, key=None, metric='create'):
        return await self.request('POST', '/api/v1/orders', who, metric,
            json={'businessId': business or who['businessId'], 'items': [{'productId': product or who['productId'], 'quantity': 1}],
                  'paymentMethod': 'Efectivo', 'expectedTotal': 10.0}, headers={'Idempotency-Key': key or str(uuid4())})

    async def cancel(self, who, order):
        return await self.request('POST', f"/api/v1/orders/{order['id']}/cancel", who, 'cancel',
                                  json={'reason': 'user_other', 'expectedVersion': order['version']})

    async def arrival(self, rate, seconds, function):
        start = time.monotonic()
        tasks = []
        for i in range(round(rate * seconds)):
            await asyncio.sleep(max(0, start + i / rate - time.monotonic()))
            tasks.append(asyncio.create_task(function(i)))
        await asyncio.gather(*tasks)
        self.details.setdefault('arrivals', []).append({'rate': rate, 'seconds': seconds, 'launched': len(tasks),
                                                      'elapsed': time.monotonic() - start})

    async def p0(self):
        async def iteration(i):
            who = self.students[i % 5]
            key = str(uuid4())
            a = await self.purchase(who, key=key)
            b = await self.purchase(who, key=key, metric='idempotency')
            self.check(a[0] == b[0] == 201 and a[2] == b[2], 'P0 idempotency mismatch')
            if a[0] == 201:
                self.check((await self.cancel(who, a[1]))[0] == 200, 'P0 cancellation')
        await self.arrival(1, 45 if not self.args.quick else 5, iteration)

    async def p5(self):
        self.reset(stock=50)
        target = self.students[0]
        results = await asyncio.gather(*(self.purchase(who, target['businessId'], target['productId']) for who in self.students[:200]))
        codes = Counter(r[0] for r in results)
        self.details['outcomes'] = dict(codes)
        self.check(codes == {201: 50, 422: 150}, 'P5 requires exactly 50 created and 150 unavailable')

    async def p6(self):
        target = self.students[0]
        async def group(who):
            key = str(uuid4())
            rows = await asyncio.gather(*(self.purchase(who, target['businessId'], target['productId'], key) for _ in range(10)))
            successful = [r for r in rows if r[0] == 201]
            self.check(bool(successful) and len({r[2] for r in successful}) == 1, 'P6 duplicate/missing order')
            self.check(all(r[0] in (201, 503) for r in rows), 'P6 unexpected response')
        await asyncio.gather(*(group(who) for who in self.students[:50]))
        with self.engine.connect() as db:
            self.check(db.scalar(text('SELECT count(*) FROM orders')) == 50, 'P6 order count')

    async def p4(self):
        target = self.students[0]
        for rate in (2, 5, 10, 20, 40):
            async def one(i):
                who = self.students[i % 1000]
                status, order, _ = await self.purchase(who, target['businessId'], target['productId'], metric=f'create_{rate}')
                self.check(status == 201, f'P4 {rate}/s creation')
                if status == 201:
                    self.check((await self.cancel(who, order))[0] == 200, f'P4 {rate}/s cancellation')
            await self.arrival(rate, 180 if not self.args.quick else 20, one)
            self.check(quantile(self.samples[f'create_{rate}'], .95) < 1500, f'P4 {rate}/s p95')

    async def p7(self):
        async def login(i):
            who = self.students[i % 1000]
            status, _, _ = await self.request('POST', '/api/v1/auth/login', name='login',
                                             json={'email': who['email'], 'password': who['password']})
            self.check(status == 200, 'P7 login')
        if self.args.quick:
            await self.arrival(20, 30, login)
        else:
            await self.arrival(10, 30, login)
            await self.arrival(20, 240, login)
            await self.arrival(10, 30, login)
        self.check(quantile(self.samples['login'], .95) < 1500, 'P7 p95')

    async def p7b(self):
        for wave in range(3):
            async def login(who):
                return await self.request('POST', '/api/v1/auth/login', name='login_wave',
                    json={'email': who['email'], 'password': who['password']})
            rows = await asyncio.gather(*(login(who) for who in self.students[:200]))
            self.check(sum(r[0] == 200 for r in rows) >= 198, f'P7b wave {wave} success <99%')
            if wave != 2:
                await asyncio.sleep(30)
        self.check(quantile(self.samples['login_wave'], .95) < 3000, 'P7b p95 >=3s')

    async def read_users(self, count, seconds, metric='read'):
        until = time.monotonic() + seconds
        async def user(who):
            await asyncio.sleep(self.random.uniform(0, min(7.5, seconds / 2)))
            while time.monotonic() < until:
                for path in ('/api/v1/businesses?limit=20', f"/api/v1/businesses/{who['businessId']}/products?limit=20",
                             '/api/v1/users/me/orders/active?limit=20'):
                    status, _, _ = await self.request('GET', path, who, metric)
                    self.check(status == 200, metric + ' HTTP failure')
                await asyncio.sleep(self.random.uniform(5, 10))
        await asyncio.gather(*(user(who) for who in self.students[:count]))

    async def p2(self):
        sizes = (50, 100, 150, 200, 250, 300) if self.args.profile == 'pessimistic' else (100, 200, 300, 400, 600, 800, 1000)
        for count in sizes:
            name = f'read_{count}'
            await self.read_users(count, 120 if not self.args.quick else 20, name)
            self.check(quantile(self.samples[name], .95) < 750, name + ' p95')
            self.check(quantile(self.samples[name], .99) < 2000, name + ' p99')

    async def realtime(self, count, seconds, toggle=True, jitter=False, kitchen=False):
        clients, received, changes = [], [], set()
        disconnected = []
        slots = asyncio.Semaphore(25)
        async def connect(index, who):
            async with slots:
                await self.auth(who)
                sio = socketio.AsyncClient(http_session=self.http, reconnection=False, logger=False, engineio_logger=False)
                async def product(event):
                    data = event['data']
                    received.append((index, data.get('businessId'), data.get('version'),
                        (time.time() - datetime.fromisoformat(event['occurredAt']).timestamp()) * 1000, event['id']))
                async def order(event):
                    self.samples['order_event'].append((time.time() - datetime.fromisoformat(event['occurredAt']).timestamp()) * 1000)
                async def disconnect(*_):
                    disconnected.append(index)
                sio.on('product.updated', product)
                sio.on('order.updated', order)
                sio.on('disconnect', disconnect)
                await sio.connect(BASE, transports=['websocket'], auth={'token': self.sessions[who['email']]['accessToken']},
                                  headers={'Origin': BASE}, wait_timeout=30)
                # user ID comes from /users/me once, never stored in reports.
                status, me, _ = await self.request('GET', '/api/v1/users/me', who)
                assert status == 200
                ack = await sio.call('subscribe', {'topics': [f"business:{who['businessId']}:products", f"user:{me['id']}:orders"]}, timeout=30)
                self.check(ack.get('ok'), 'P8 subscription denied')
                clients.append(sio)
        await asyncio.gather(*(connect(i, who) for i, who in enumerate(self.students[:count])))
        self.details['connections'] = len(clients)
        until = time.monotonic() + seconds
        async def toggles(index, operator):
            product_id = self.students[index]['productId']
            enabled = True
            while time.monotonic() < until:
                delay = self.random.uniform(20, 40) if jitter else 5
                await asyncio.sleep(min(delay, max(0, until - time.monotonic())))
                if time.monotonic() >= until:
                    break
                enabled = not enabled
                status, result, _ = await self.request('PATCH', f'/api/v1/products/{product_id}/availability', operator, 'toggle', json={'isAvailable': enabled})
                self.check(status == 200, 'P8 toggle failed')
                if status == 200:
                    changes.add((operator['businessId'], result['version']))
        try:
            tasks = [asyncio.create_task(toggles(i, op)) for i, op in enumerate(self.operators)] if toggle else []
            if kitchen:
                tasks.append(asyncio.create_task(self.kitchen(1.5, seconds)))
            if tasks:
                await asyncio.gather(*tasks)
            else:
                await asyncio.sleep(seconds)
            await asyncio.sleep(2)
            self.check(not disconnected, 'P8 unexpected disconnect')
            unique = {(i, business, version, eid) for i, business, version, _, eid in received if (business, version) in changes}
            expected = sum(sum(who['businessId'] == business for who in self.students[:count]) for business, _ in changes)
            self.details.update(expectedEvents=expected, receivedEvents=len(unique), changes=len(changes), unexpectedDisconnects=len(disconnected))
            if toggle:
                self.check(expected > 0 and len(unique) == expected, 'P8 event loss')
                self.samples['product_event'] = [latency for _, business, version, latency, _ in received if (business, version) in changes]
                self.check((quantile(self.samples['product_event'], .95) or math.inf) < (1000 if count == 300 else 2000), 'P8 event p95')
        finally:
            await asyncio.gather(*(sio.disconnect() for sio in clients), return_exceptions=True)

    async def kitchen(self, rate, seconds):
        orders, done, accepted, tasks = {}, set(), [], []
        stop = asyncio.Event()
        async def create(i):
            who = self.students[i % (300 if self.args.scenario == 'P8b' else 1000)]
            status, order, _ = await self.purchase(who, metric='kitchen_create')
            self.check(status == 201, 'P9 create failed')
            if status == 201:
                orders[order['id']] = {'code': order['pickupCode'], 'created': time.monotonic(), 'prepare': None, 'walk': None}
        async def tablet(operator):
            while not stop.is_set():
                status, page, _ = await self.request('GET', f"/api/v1/businesses/{operator['businessId']}/orders/active?limit=100", operator, 'kitchen_read')
                self.check(status == 200, 'P9 kitchen read')
                for order in page.get('data', []):
                    state = orders.get(order['id'])
                    if state is None:
                        continue
                    action = None
                    if order['status'] == 'pending':
                        action = 'accept'
                    elif order['status'] == 'accepted':
                        action = 'start'
                    elif order['status'] == 'preparing':
                        state['prepare'] = state['prepare'] or time.monotonic() + self.random.uniform(20, 60)
                        if time.monotonic() >= state['prepare']:
                            action = 'ready'
                    elif order['status'] == 'ready':
                        state['walk'] = state['walk'] or time.monotonic() + self.random.uniform(5, 30)
                        if time.monotonic() >= state['walk']:
                            action = 'complete'
                    if action:
                        data = {'expectedVersion': order['version']}
                        if action == 'complete':
                            data.update(method='manual', code=state['code'])
                        result, _, _ = await self.request('POST', f"/api/v1/orders/{order['id']}/{action}", operator, 'kitchen_transition', json=data)
                        self.check(result in (200, 409), 'P9 transition error')
                        if result == 200 and action == 'accept':
                            accepted.append((time.monotonic() - state['created']) * 1000)
                        if result == 200 and action == 'complete':
                            done.add(order['id'])
                await asyncio.sleep(2)
        tasks = [asyncio.create_task(tablet(op)) for op in self.operators for _ in range(2)]
        try:
            await self.arrival(rate, seconds, create)
            deadline = time.monotonic() + 300
            while len(done) < len(orders) and time.monotonic() < deadline:
                await asyncio.sleep(2)
        finally:
            stop.set()
            await asyncio.gather(*tasks)
        self.samples['acceptance'] = accepted
        self.details.update(created=len(orders), delivered=len(done))
        self.check(len(orders) > 0 and len(done) / len(orders) >= .99, 'P9 delivery ratio')
        self.check((quantile(accepted, .95) or math.inf) < 10000, 'P9 acceptance p95')
        self.check((quantile(self.samples['kitchen_create'], .95) or math.inf) < 1500, 'P9 creation p95')

    async def resources(self):
        while self.running:
            try:
                def collect():
                    output = subprocess.check_output(COMPOSE + ['stats', '--no-stream', '--format', 'json'], text=True, timeout=10)
                    sql = {}
                    with self.engine.connect() as db:
                        sql['active'] = db.scalar(text("SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND state='active'"))
                        sql['idleTransaction'] = db.scalar(text("SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND state='idle in transaction'"))
                        sql['outboxLag'] = float(db.scalar(text('SELECT coalesce(extract(epoch FROM now()-min(created_at)),0) FROM outbox_events WHERE published_at IS NULL')))
                    return {'elapsed': time.monotonic() - self.started, 'containers': [json.loads(x) for x in output.splitlines() if x], 'sql': sql}
                self.monitor.append(await asyncio.to_thread(collect))
            except Exception as error:
                self.details['monitorError'] = type(error).__name__
            await asyncio.sleep(5)

    async def run(self):
        self.started = time.monotonic()
        async with aiohttp.ClientSession(connector=aiohttp.TCPConnector(limit=2000), cookie_jar=aiohttp.DummyCookieJar(),
                                         timeout=aiohttp.ClientTimeout(total=15)) as self.http:
            await self.prepare()
            self.reset()
            monitor = asyncio.create_task(self.resources())
            try:
                scenario = self.args.scenario
                if scenario in ('P0', 'P2', 'P4', 'P5', 'P6', 'P7', 'P7b'):
                    await getattr(self, scenario.lower())()
                elif scenario == 'P8':
                    await self.realtime(300, 1200 if not self.args.quick else 45)
                elif scenario == 'P8-1000':
                    await self.realtime(1000, 300 if not self.args.quick else 45)
                elif scenario == 'P8-idle':
                    await self.realtime(300, 360 if not self.args.quick else 95, jitter=True)
                elif scenario == 'P8b':
                    await self.realtime(300, 1200 if not self.args.quick else 60, toggle=False, kitchen=True)
                elif scenario == 'P9':
                    await self.kitchen(1.5, 1200 if not self.args.quick else 60)
                elif scenario == 'P9-burst':
                    await self.kitchen(4.5, 300 if not self.args.quick else 60)
                elif scenario == 'P12':
                    await asyncio.gather(self.read_users(300, 7200, 'soak_read'), self.kitchen(1.5, 7200))
                else:
                    raise ValueError('Unknown scenario')
                await asyncio.sleep(2)
                self.details['integrity'] = self.integrity()
            except Exception as error:
                self.failures.append('Execution failed: ' + type(error).__name__)
                raise
            finally:
                self.running = False
                monitor.cancel()
                await asyncio.gather(monitor, return_exceptions=True)
                for name, codes in self.statuses.items():
                    self.check(codes[500] == 0 and codes[0] == 0, name + ' internal/transport errors')
                metrics = {name: {'count': len(values), 'p50Ms': quantile(values, .5), 'p95Ms': quantile(values, .95),
                                  'p99Ms': quantile(values, .99), 'status': dict(self.statuses[name])} for name, values in self.samples.items()}
                report = {'scenario': self.args.scenario, 'profile': self.args.profile, 'quick': self.args.quick,
                    'commit': os.environ.get('GITHUB_SHA'), 'elapsedSeconds': time.monotonic() - self.started,
                    'success': not self.failures, 'failures': dict(Counter(self.failures)), 'details': self.details,
                    'metrics': metrics, 'resources': self.monitor}
                self.auth_path.write_text(json.dumps(self.sessions))
                self.auth_path.chmod(0o600)
                Path(self.args.output).write_text(json.dumps(report, indent=2) + '\n')
                print(json.dumps({key: report[key] for key in ('scenario', 'profile', 'quick', 'elapsedSeconds', 'success', 'failures')}), flush=True)
        self.engine.dispose()
        return 0 if not self.failures else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixtures', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--profile', choices=['base', 'pessimistic'], default='base')
    parser.add_argument('--scenario', required=True)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--quick', action='store_true')
    mode.add_argument('--full', action='store_true')
    args = parser.parse_args()
    return asyncio.run(Run(args).run())


if __name__ == '__main__':
    raise SystemExit(main())
