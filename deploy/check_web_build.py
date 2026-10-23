"""Check deployable web artifacts without connecting to Firebase or an API."""
import argparse
from pathlib import Path
import re


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--base', required=True)
    parser.add_argument('--mode', choices=['firebase', 'rest'], required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'/(?:[A-Za-z0-9_-]+/)*', args.base):
        parser.error('--base must be / or an absolute path ending in /')
    root = args.directory
    for filename in ['index.html', 'flutter_bootstrap.js', 'main.dart.js', 'manifest.json']:
        if not (root / filename).is_file():
            parser.error('Missing artifact: ' + filename)
    html = (root / 'index.html').read_text()
    if f'<base href="{args.base}">' not in html or 'src="flutter_bootstrap.js"' not in html:
        parser.error('Wrong base href or missing Flutter bootstrap')
    if args.mode == 'firebase':
        for filename in ['snackup_service_worker.js', 'pwa.js', 'offline.html']:
            if not (root / filename).is_file():
                parser.error('Missing PWA artifact: ' + filename)
        if 'firebase-app-compat.js' not in html:
            parser.error('Firebase integration unexpectedly changed')
    else:
        if 'firebase-app-compat.js' in html:
            parser.error('Unexpected Firebase bootstrap in the REST portal')
        javascript = (root / 'main.dart.js').read_bytes()
        for marker in [b'Entrar al local de prueba', b'SnackUP-Prueba-2026', b'negocio@snackup.test']:
            if marker in javascript:
                parser.error('Review-only content present in release build')
    print('Web artifacts validated; base=' + args.base + ', mode=' + args.mode)


if __name__ == '__main__':
    main()
