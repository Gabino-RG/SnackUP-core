"""Readiness includes SQL, Redis, the proxy and each frontend's actual HTML."""
import os
from urllib.parse import urlsplit
from urllib.request import Request, urlopen


def fetch(port, path):
    host = urlsplit(os.environ['SNACKUP_PUBLIC_ORIGIN']).netloc
    request = Request(f'http://127.0.0.1:{port}{path}', headers={'Host': host})
    with urlopen(request, timeout=2) as response:
        if response.status != 200:
            raise RuntimeError('Unhealthy response')
        return response.read(65536)


def api_ready():
    return b'"ready"' in fetch(8000, '/health/ready')


def check():
    if b'"ready"' not in fetch(8081, '/health/ready'):
        raise RuntimeError('API is not ready through the proxy')
    for path, base in [('/', b'<base href="/">'), ('/paneles/', b'<base href="/paneles/">')]:
        html = fetch(8081, path)
        if base not in html or b'flutter_bootstrap.js' not in html:
            raise RuntimeError('Frontend is missing or uses the wrong base path')


if __name__ == '__main__':
    check()
