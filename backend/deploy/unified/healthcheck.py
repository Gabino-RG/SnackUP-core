"""Readiness includes SQL, Redis, the proxy and each frontend's actual HTML."""
import os
from pathlib import Path
import time
from urllib.parse import urlsplit
from urllib.request import Request, urlopen


def fetch(port, path, origin=None):
    host = urlsplit(origin or os.environ['SNACKUP_PUBLIC_ORIGIN']).netloc
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
    origins = (os.environ['SNACKUP_PUBLIC_ORIGIN'],
               os.environ.get('SNACKUP_KITCHEN_PUBLIC_ORIGIN', 'http://cocina.localhost'),
               os.environ.get('SNACKUP_ADMINISTRATION_PUBLIC_ORIGIN', 'http://administracion.localhost'))
    for origin in origins:
        base = b'<base href="/">'
        html = fetch(8081, '/', origin)
        if base not in html or b'flutter_bootstrap.js' not in html:
            raise RuntimeError('Frontend is missing or uses the wrong base path')


if __name__ == '__main__':
    check()
