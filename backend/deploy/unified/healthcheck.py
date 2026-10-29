"""Readiness includes SQL, Redis, the proxy and each frontend's actual HTML."""
import os
from pathlib import Path
import time
from urllib.parse import urlsplit
from urllib.request import Request, urlopen


def fetch(port, path):
    host = urlsplit(os.environ['SNACKUP_PUBLIC_ORIGIN']).netloc
    request = Request(f'http://127.0.0.1:{port}{path}', headers={'Host': host})
    with urlopen(request, timeout=2) as response:
        if response.status != 200:
            raise RuntimeError('Unhealthy response')
        return response.read(65536)


def api_ready(port=8000):
    return b'"ready"' in fetch(port, '/health/ready')


def check():
    if not all(api_ready(port) for port in range(8000, 8000 + int(os.environ.get("SNACKUP_WORKERS", "2")))):
        raise RuntimeError("An API worker is not ready")
    if time.time() - Path("/tmp/snackup-jobs-heartbeat").stat().st_mtime > 180:
        raise RuntimeError("Scheduled jobs are not running")
    if b'"ready"' not in fetch(8081, '/health/ready'):
        raise RuntimeError('API is not ready through the proxy')
    for path, base in [('/', b'<base href="/">'), ('/paneles/', b'<base href="/paneles/">')]:
        html = fetch(8081, path)
        if base not in html or b'flutter_bootstrap.js' not in html:
            raise RuntimeError('Frontend is missing or uses the wrong base path')


if __name__ == '__main__':
    check()
