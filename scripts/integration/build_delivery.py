"""Compile and package ONLY the REST panels, with review mode disabled.

Run at repository root with Python 3.10+ and Flutter 3.32.0.
The resulting ZIP contains static web files, contract, docs and exact sources.
No deployment, database creation, credentials or production claims are involved.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
from urllib.parse import urlsplit
import zipfile

ROOT = Path(__file__).resolve().parents[2]
REQUIRED_WEB = {'index.html', 'main.dart.js', 'flutter_bootstrap.js', 'vendor/zxing-0.21.3.min.js'}
DOCS = [
    'docs/integracion/README.md', 'docs/integracion/openapi.json',
    'docs/integracion/REALTIME.md', 'docs/integracion/ACEPTACION.md',
    'docs/integracion/nginx.conf.example', 'docs/MANUAL_BACKEND_PANELES.md',
    'docs/CONTRATO_PANELES.md', 'docs/PORTAL_API_LOCAL.md',
]
README = '''SNACKUP - ENTREGA FRONTEND ADMINISTRACION Y COCINA

1. Lee documentos/README.md y documentos/ACEPTACION.md.
2. Implementa la API de documentos/openapi.json en /api/v1/.
3. Sirve web/ en la raiz del mismo origen HTTPS que la API.
4. Conserva rutas API y /media/ fuera del fallback de la web.
5. Ejecuta las pruebas de aceptacion con cuentas autorizadas del backend.

Esta compilacion usa lib/main_portal_api.dart y REVIEW_MODE=false.
No incluye servidor productivo, base de datos ni cuentas automaticas.
Sin backend aparecera un error de conexion: no se sustituyen datos reales
por ejemplos. No abrir index.html con doble clic; necesita un servidor HTTP.

VERSION.json identifica fuente, compilador, configuracion y huella del codigo.
SHA256SUMS.txt permite comprobar todos los archivos del paquete.
fuente.zip contiene el repositorio del commit indicado, con sus pruebas.
El manual 1.0 es la referencia historica. La guia de integracion explica
esta entrega. Integracion SQL, correo, Google y carga requieren al backend.
'''


def git(*args, binary=False):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=not binary).strip() if not binary else subprocess.check_output(['git', *args], cwd=ROOT)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def validate_api(value):
    uri = urlsplit(value)
    if value == '/api/v1/':
        return value
    if (uri.scheme != 'https' or not uri.hostname or uri.username or uri.password
            or uri.query or uri.fragment or not uri.path.endswith('/')):
        raise ValueError('API must be /api/v1/ or an absolute HTTPS URL ending in /, without credentials/query/fragment.')
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', default=shutil.which('flutter') or 'flutter')
    parser.add_argument('--api-base-url', default='/api/v1/')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/delivery/SnackUP-Paneles-Frontend.zip')
    args = parser.parse_args()
    api = validate_api(args.api_base_url)
    if git('status', '--porcelain'):
        raise ValueError('Commit the reviewed source first. Delivery requires a clean working tree.')
    if args.output.exists():
        raise ValueError('Output already exists. Select a new --output path.')
    commit = git('rev-parse', 'HEAD')
    branch = git('branch', '--show-current')
    version = json.loads(subprocess.check_output([args.flutter, '--version', '--machine'], cwd=ROOT, text=True))
    if version['frameworkVersion'] != '3.32.0':
        raise ValueError('Use the pinned Flutter 3.32.0 toolchain.')
    build = ROOT / 'app/build/portal-entrega'
    command = [args.flutter, 'build', 'web', '--no-web-resources-cdn', '--pwa-strategy=none',
               '--target', 'lib/main_portal_api.dart', '--dart-define=BACKEND=rest',
               '--dart-define=REVIEW_MODE=false', '--dart-define=API_BASE_URL=' + api,
               '--output', 'build/portal-entrega']
    subprocess.run(command, cwd=ROOT / 'app', check=True)
    if git('status', '--porcelain') or git('rev-parse', 'HEAD') != commit:
        raise ValueError('Build changed versioned sources. Review and commit before packaging.')
    names = {p.relative_to(build).as_posix() for p in build.rglob('*') if p.is_file()}
    if not REQUIRED_WEB <= names:
        raise ValueError('Incomplete web compilation: ' + str(REQUIRED_WEB - names))
    main_js = (build / 'main.dart.js').read_bytes()
    for marker in [b'Entrar al local de prueba', b'SnackUP-Prueba-2026', b'negocio@snackup.test', b'review/orders']:
        if marker in main_js:
            raise ValueError('Review-only content leaked into production frontend.')
    source_zip = git('archive', '--format=zip', commit, binary=True)
    with zipfile.ZipFile(io.BytesIO(source_zip)) as archive:
        forbidden = [n for n in archive.namelist() if Path(n).name in {'.env', 'credentials.json', 'service-account.json', 'serviceAccountKey.json'} or Path(n).suffix.lower() in {'.pem', '.p12', '.pfx', '.key'}]
        if forbidden:
            raise ValueError('Potential secret material in sources: ' + ', '.join(forbidden))
    payload = {'web/' + n: (build / n).read_bytes() for n in sorted(names)}
    payload['fuente.zip'] = source_zip
    payload['LEEME.txt'] = README.encode('utf-8')
    for doc in DOCS:
        payload['documentos/' + Path(doc).name] = (ROOT / doc).read_bytes()
    manifest = {
        'product': 'SnackUP - Administración y Cocina',
        'release': 'frontend-integration-1.0.0',
        'created_utc': datetime.now(timezone.utc).isoformat(),
        'branch': branch, 'commit': commit, 'tree': git('rev-parse', 'HEAD^{tree}'),
        'source_zip_sha256': sha(source_zip),
        'entrypoint': 'lib/main_portal_api.dart', 'backend': 'rest',
        'api_base_url': api, 'review_mode': False, 'service_worker': False,
        'flutter': version['frameworkVersion'], 'dart': version['dartSdkVersion'],
        'openapi_sha256': sha(payload['documentos/openapi.json']),
        'production_backend_integrated': False,
        'note': 'Frontend prepared for integration. Acceptance against the definitive backend is pending.',
    }
    payload['VERSION.json'] = (json.dumps(manifest, indent=2, ensure_ascii=False) + '\n').encode('utf-8')
    payload['SHA256SUMS.txt'] = ''.join(f'{sha(data)}  {name}\n' for name, data in sorted(payload.items())).encode('utf-8')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.output, 'x', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in sorted(payload.items()):
            archive.writestr('SnackUP-Paneles-Frontend/' + name, data)
    with zipfile.ZipFile(args.output) as archive:
        if archive.testzip():
            raise ValueError('Corrupt ZIP')
        prefix = 'SnackUP-Paneles-Frontend/'
        for line in archive.read(prefix + 'SHA256SUMS.txt').decode().splitlines():
            digest, name = line.split('  ', 1)
            if sha(archive.read(prefix + name)) != digest:
                raise ValueError('Hash mismatch: ' + name)
    print(json.dumps({'output': str(args.output.resolve()), 'sha256': sha(args.output.read_bytes()), 'files': len(payload), 'commit': commit}))


if __name__ == '__main__':
    main()
