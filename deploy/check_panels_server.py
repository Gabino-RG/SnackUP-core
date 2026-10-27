"""Read-only deployment probe for Kitchen/Admin; no credentials or student UI."""
import argparse
import json
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import build_opener, HTTPRedirectHandler


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def origin(value):
    parsed = urlsplit(value)
    if (parsed.scheme != 'https' or not parsed.hostname or parsed.username
            or parsed.password or parsed.query or parsed.fragment or parsed.path not in ('', '/')):
        raise ValueError('Usa https://DOMINIO, sin credenciales, ruta ni parámetros.')
    return value.rstrip('/')


def inspect(base, fetch):
    checks = []
    for path, kind in [('/health/live', 'live'), ('/health/ready', 'ready'),
                       ('/paneles/', 'html'), ('/paneles/flutter_bootstrap.js', 'js'),
                       ('/paneles/main.dart.js', 'js'),
                       ('/api/legacy/v1/auth/options', 'json')]:
        try:
            status, headers, body = fetch(base + path)
            assert status == 200, 'HTTP inesperado'
            media = headers.get('Content-Type', '').lower()
            if kind in ('live', 'ready', 'json'):
                assert 'application/json' in media, 'La API devolvió otro formato'
                data = json.loads(body)
                assert isinstance(data, dict), 'JSON inesperado'
                if kind in ('live', 'ready'):
                    assert data.get('status') == ('ok' if kind == 'live' else 'ready'), 'Servicio no disponible'
            if kind in ('html', 'js'):
                assert headers.get('X-Content-Type-Options') == 'nosniff', 'Falta nosniff'
                assert headers.get('X-Frame-Options') == 'DENY', 'Falta protección de marcos'
                assert 'no-cache' in headers.get('Cache-Control', ''), 'Caché de versión no revalidable'
            if kind == 'html':
                assert 'text/html' in media and b'<base href="/paneles/">' in body, 'Ruta de paneles incorrecta'
            if kind == 'js':
                assert 'javascript' in media and body.strip(), 'No se entregó JavaScript'
            checks.append({'path': path, 'passed': True})
        except Exception as error:
            # Never persist response bodies, query strings, tokens or server errors.
            checks.append({'path': path, 'passed': False, 'reason': str(error) if isinstance(error, AssertionError) else type(error).__name__})
    return {'passed': all(c['passed'] for c in checks), 'checks': checks,
            'scope': 'HTTPS, rutas y disponibilidad. No certifica carga, permisos, SMTP, tareas ni restauración.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    try:
        base = origin(args.url)
    except ValueError as error:
        parser.error(str(error))
    opener = build_opener(NoRedirect())

    def fetch(url):
        with opener.open(url, timeout=20) as response:
            # main.dart.js may be large. A prefix is sufficient to reject HTML.
            return response.status, response.headers, response.read(65536)

    report = inspect(base, fetch)
    args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print('Comprobación aprobada.' if report['passed'] else 'Hay comprobaciones fallidas. Consulta el informe.')
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
