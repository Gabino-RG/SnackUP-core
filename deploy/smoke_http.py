"""Exercise a running static container; no account or external service is used."""
import argparse
import json
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def check(origin, path, status=200, method='GET'):
    try:
        response = urlopen(Request(origin.rstrip('/') + path, method=method), timeout=10)
    except HTTPError as error:
        response = error
    with response:
        assert response.status == status, (path, response.status, status)
        return response.headers, response.read()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='http://127.0.0.1:18080')
    parser.add_argument('--base', default='/')
    parser.add_argument('--pwa', action='store_true')
    args = parser.parse_args()
    headers, body = check(args.url, '/healthz')
    assert body == b'ok' and headers['Cache-Control'] == 'no-store'
    _, html = check(args.url, '/')
    assert ('<base href="' + args.base + '">').encode() in html
    assert b'src="flutter_bootstrap.js"' in html
    assert check(args.url, '/a/deep/route')[1] == html
    check(args.url, '/a/deep/route', 405, method='POST')
    check(args.url, '/missing-file.js', 404)
    for filename in ['main.dart.js', 'flutter_bootstrap.js', 'manifest.json']:
        headers, _ = check(args.url, '/' + filename, method='HEAD')
        assert headers['Cache-Control'] == 'no-cache', filename
        assert 'text/html' not in headers.get('Content-Type', ''), filename
    for path in ['/api', '/api/v1/auth/options', '/api/legacy/v1/auth/options',
                 '/socket.io/?EIO=4&transport=websocket', '/media/private.webp']:
        headers, body = check(args.url, path, 503)
        assert headers['Content-Type'].startswith('application/json')
        assert json.loads(body)['error']['code'] == 'BACKEND_NOT_CONFIGURED'
    if args.pwa:
        _, manifest = check(args.url, '/manifest.json')
        manifest = json.loads(manifest)
        assert manifest['id'] == '.' and manifest['scope'] == '.'
        for filename in ['pwa.js', 'snackup_service_worker.js', 'offline.html']:
            check(args.url, '/' + filename)
    print('Container HTTP checks passed; base=' + args.base)


if __name__ == '__main__':
    main()
