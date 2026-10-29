"""Run Flutter repository integration against an isolated, pinned FastAPI checkout.

Never accepts a remote URL or an existing database. All identities are synthetic.
Usage: python scripts/integration/live_backend.py --backend ../SnackUP-backend-v32/backend
"""
import argparse
from datetime import timedelta
from contextlib import ExitStack, contextmanager
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import tempfile
import threading
import time
from urllib.parse import urlsplit, urlunsplit
from uuid import uuid4

BACKEND_REVISION = '330825c47ec845f00c9f5e58c5c10c5ebe02f364'


@contextmanager
def isolated_database(root):
    admin_url = os.environ.get('SNACKUP_TEST_POSTGRES_ADMIN_URL')
    if not admin_url:
        yield 'sqlite:///' + (root / 'test.db').as_posix()
        return
    parsed = urlsplit(admin_url)
    if parsed.scheme != 'postgresql' or parsed.hostname not in ('127.0.0.1', 'localhost') or parsed.query:
        raise ValueError('PostgreSQL test service must be loopback, without query parameters')
    import psycopg
    from psycopg import sql
    name = 'snackup_test_' + uuid4().hex
    with psycopg.connect(admin_url, autocommit=True) as admin:
        admin.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(name)))
        try:
            yield urlunsplit(parsed._replace(scheme='postgresql+psycopg', path='/' + name))
        finally:
            admin.execute(sql.SQL('DROP DATABASE {} WITH (FORCE)').format(sql.Identifier(name)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backend', type=Path, required=True)
    parser.add_argument('--flutter', default='flutter')
    parser.add_argument('--web', type=Path, help='Compiled /paneles/ build for the browser smoke test')
    parser.add_argument('--node', default='node')
    parser.add_argument('--resilience', action='store_true', help='Also exercise concurrent requests, closure and browser network failures')
    args = parser.parse_args()
    backend = args.backend.resolve()
    revision = subprocess.check_output(['git', '-C', str(backend), 'rev-parse', 'HEAD'], text=True).strip()
    expected = subprocess.check_output(['git', '-C', str(backend), 'rev-parse', BACKEND_REVISION], text=True).strip()
    if revision != expected:
        parser.error('The backend must be checked out at the pinned V3.2 revision ' + BACKEND_REVISION)
    if subprocess.check_output(['git', '-C', str(backend), 'status', '--porcelain', '--untracked-files=no'], text=True).strip():
        parser.error('Use an unmodified backend checkout so results identify the tested code.')
    panel_contract = json.loads((Path(__file__).resolve().parents[2] / 'docs/integracion/openapi.json').read_text(encoding='utf-8'))
    server_contract = json.loads((backend / 'contracts/panels.openapi.json').read_text(encoding='utf-8'))
    for section in ('paths', 'components'):
        if panel_contract[section] != server_contract[section]:
            parser.error('The portal and delivered backend disagree on contract ' + section)
    sys.path.insert(0, str(backend))
    import uvicorn
    from snackup.main import create_app
    from snackup.config import Settings
    from snackup.auth import hash_password
    from snackup.db import Base, utcnow
    from snackup.identity_models import User, Career, AcademicGroup, AcademicRecord
    from snackup.operation_models import Business, Product, Order, OrderItem

    # Reserve the socket before starting to avoid port selection races.
    listener = socket.socket()
    listener.bind(('127.0.0.1', 0))
    origin = 'http://127.0.0.1:' + str(listener.getsockname()[1])
    with tempfile.TemporaryDirectory(prefix='snackup-live-') as folder, ExitStack() as cleanup:
        cleanup.callback(listener.close)
        root = Path(folder)
        database_url = cleanup.enter_context(isolated_database(root))
        password = secrets.token_urlsafe(32)
        settings = Settings(_env_file=None, environment='test',
            secret_key=secrets.token_urlsafe(48), database_url=database_url,
            public_origin=origin, redis_url='', background_events=True, push_enabled=False,
            media_dir=root / 'media', web_dir=None, smtp_host='', smtp_from='',
            admin_email_domains='staff.example.edu', student_email_domains='students.example.edu')
        app = create_app(settings)
        cleanup.callback(app.state.db.dispose)
        if args.web:
            from fastapi.staticfiles import StaticFiles
            app.mount('/paneles', StaticFiles(directory=args.web.resolve(), html=True), name='panels')
        Base.metadata.create_all(app.state.db.engine)
        hashed = hash_password(password)
        with app.state.db.sessions.begin() as db:
            db.add(Career(id='career-1', name='Desarrollo de Software'))
            db.flush()
            db.add(AcademicGroup(id='group-1', career_id='career-1', name='DSM-1'))
            db.add_all([Business(id=f'business-{i}', name=f'Cafetería {i}', is_open=True,
                cafeteria_id='cafeteria', cafeteria_name='Cafetería universitaria') for i in (1, 2)])
            db.flush()
            for name, role, business in [('master', 'admin', None), ('operator', 'business', 'business-1'),
                                         ('operator2', 'business', 'business-2'),
                                         ('student', 'user', None)]:
                email = name + ('@students.example.edu' if role == 'user' else '@staff.example.edu')
                db.add(User(id=name, email=email, display_name=name, password_hash=hashed,
                    role=role, business_id=business, is_master=name == 'master',
                    is_active=True, email_verified=True, approval_status='approved'))
                if role == 'user':
                    db.add(AcademicRecord(email=email, institutional_id='SYNTHETIC-1', display_name=name,
                        kind='student', career_id='career-1', group_id='group-1', source='isolated integration'))
            db.add(Product(id='product-1', business_id='business-1', name='Torta', category='Comida', price='35.50', stock=10))
            db.add(Product(id='product-2', business_id='business-2', name='Pedido antiguo de prueba', category='Comida', price='10.00', stock=5))
            db.flush()
            expired = Order(id='expired-order', business_id='business-2', student_id='student', order_number=1,
                customer_name='student', total='10.00', pickup_code='00000000', status='ready',
                ready_at=utcnow() - timedelta(hours=2), created_at=utcnow() - timedelta(hours=3))
            expired.items = [OrderItem(product_id='product-2', name='Pedido antiguo de prueba', quantity=1, price='10.00', reserved_quantity=1)]
            db.add(expired)
        server = uvicorn.Server(uvicorn.Config(app, log_level='warning', access_log=False))
        worker = threading.Thread(target=server.run, kwargs={'sockets': [listener]}, daemon=True)
        worker.start()
        try:
            deadline = time.monotonic() + 20
            while not server.started:
                if not worker.is_alive() or time.monotonic() >= deadline:
                    raise RuntimeError('The disposable backend failed to start')
                time.sleep(.05)
            print('Testing Flutter clients against backend ' + revision, flush=True)
            env = {**os.environ, 'SNACKUP_LIVE_ORIGIN': origin, 'SNACKUP_LIVE_PASSWORD': password}
            result = subprocess.run([args.flutter, 'test', 'test_live/backend_v32_test.dart', '--reporter', 'expanded'],
                cwd=Path(__file__).resolve().parents[2] / 'app', env=env, timeout=180)
            if result.returncode == 0 and args.web:
                result = subprocess.run([args.node, 'scripts/integration/live_browser.cjs'],
                    cwd=Path(__file__).resolve().parents[2], env=env, timeout=240)
            if result.returncode == 0 and args.resilience:
                from resilience_scenarios import run
                fixtures = run(app, settings, origin, password)
                if args.web:
                    env['SNACKUP_RESILIENCE_FIXTURES'] = json.dumps(fixtures)
                    result = subprocess.run([args.node, 'scripts/integration/resilience_browser.cjs'],
                        cwd=Path(__file__).resolve().parents[2], env=env, timeout=180)
        finally:
            server.should_exit = True
            worker.join(timeout=15)
        return result.returncode


if __name__ == '__main__':
    sys.exit(main())
