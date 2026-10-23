"""Exercise real proxy routing and child cleanup without Docker or accounts."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener

import pytest

DIRECTORY = Path(__file__).parents[1] / 'deploy/unified'
spec = importlib.util.spec_from_file_location('unified_runner', DIRECTORY / 'run.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def test_failed_child_is_detected_and_remaining_processes_are_stopped():
    processes = runner.Processes()
    alive = processes.start('alive', [sys.executable, '-c', 'import time; time.sleep(60)'])
    failed = processes.start('failed', [sys.executable, '-c', 'raise SystemExit(7)'])
    try:
        failed.wait(timeout=5)
        with pytest.raises(RuntimeError, match='failed exited with status 7'):
            processes.check()
    finally:
        processes.stop()
    assert alive.poll() is not None
    assert failed.returncode == 7


def test_readiness_wait_observes_stop_signal():
    processes = runner.Processes()
    processes.stopping = True
    with pytest.raises(InterruptedError):
        runner.wait_for(lambda: False, processes)


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


@pytest.fixture
def proxy(tmp_path):
    caddy = os.environ.get('CADDY_BIN') or shutil.which('caddy')
    if not caddy:
        pytest.skip('CADDY_BIN is required for the real proxy test; CI runs the complete Docker image')
    roots = {}
    for name, base in [('usuarios', '/'), ('paneles', '/paneles/')]:
        root = tmp_path / name
        root.mkdir()
        (root / 'index.html').write_text(f'<html><base href="{base}">{name}<script src="flutter_bootstrap.js"></script></html>')
        (root / 'main.dart.js').write_text('/* ' + name + ' */')
        roots[name] = str(root)

    class Backend(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(404)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'path': self.path, 'error': {'code': 'NOT_FOUND'}}).encode())

        def log_message(self, *args):
            pass

    backend = ThreadingHTTPServer(('127.0.0.1', 0), Backend)
    thread = threading.Thread(target=backend.serve_forever, daemon=True)
    thread.start()
    import socket
    with socket.socket() as port_probe:
        port_probe.bind(('127.0.0.1', 0))
        port = port_probe.getsockname()[1]
    routes = (DIRECTORY / 'routes.caddy').read_text().replace('127.0.0.1:8000', f'127.0.0.1:{backend.server_port}')
    config = tmp_path / 'Caddyfile'
    config.write_text('{\n admin off\n auto_https off\n}\n' + routes +
                      f'\nhttp://127.0.0.1:{port} {{\n import snackup_routes\n}}\n')
    env = dict(os.environ, SNACKUP_USERS_WEB=roots['usuarios'], SNACKUP_PANELS_WEB=roots['paneles'],
               XDG_DATA_HOME=str(tmp_path / 'caddy-data'), XDG_CONFIG_HOME=str(tmp_path / 'caddy-config'))
    process = subprocess.Popen([caddy, 'run', '--config', str(config), '--adapter', 'caddyfile'],
                               env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    opener = build_opener(ProxyHandler({}), NoRedirect())

    def get(path):
        try:
            response = opener.open(Request(f'http://127.0.0.1:{port}{path}'), timeout=3)
        except HTTPError as error:
            response = error
        with response:
            return response.status, response.headers, response.read()

    try:
        for _ in range(100):
            if process.poll() is not None:
                pytest.fail(process.stderr.read().decode())
            try:
                get('/')
                break
            except OSError:
                time.sleep(0.05)
        else:
            pytest.fail('Caddy did not become ready')
        yield get
    finally:
        process.terminate()
        process.communicate(timeout=5)
        backend.shutdown()
        backend.server_close()
        thread.join(timeout=5)


def test_proxy_keeps_two_spas_separate_and_assets_are_not_html(proxy):
    for prefix, name in [('/', b'usuarios'), ('/paneles/', b'paneles')]:
        status, headers, html = proxy(prefix)
        assert status == 200 and name in html
        assert headers['Cache-Control'] == 'no-cache'
        assert proxy(prefix + 'some/deep/link')[2] == html
        assert proxy(prefix + 'main.dart.js')[2] == b'/* ' + name + b' */'
        assert proxy(prefix + 'missing.js')[0] == 404
    status, headers, _ = proxy('/paneles')
    assert status == 308 and headers['Location'] == '/paneles/'


@pytest.mark.parametrize('path', ['/api/v1/missing?x=1', '/api/legacy/v1/missing',
                                 '/socket.io/?EIO=4&transport=websocket', '/media/missing.png', '/health/missing'])
def test_proxy_preserves_private_routes_and_errors(proxy, path):
    status, headers, body = proxy(path)
    assert status == 404
    assert headers['Content-Type'] == 'application/json'
    assert json.loads(body)['path'] == path
