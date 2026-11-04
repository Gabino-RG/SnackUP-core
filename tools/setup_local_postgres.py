"""Prepare a private PostgreSQL 17 cluster for the laptop integration environment.

Keeps config and data outside Git. Repeated runs preserve both. Does not install
a Windows service, change other databases, or print credentials.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit, urlunsplit

import psycopg
from psycopg import sql


DEFAULT_ROOT = Path('C:/Users/video/Documents/JC/SnackUP-Integracion-Local')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=DEFAULT_ROOT)
    args = parser.parse_args()
    root = args.root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    binaries = root / 'runtime/pgsql/bin'
    cluster = root / 'postgres-data'
    logs = root / 'logs'
    logs.mkdir(exist_ok=True)
    (root / 'media').mkdir(exist_ok=True)
    for name in ('initdb.exe', 'pg_ctl.exe'):
        if not (binaries / name).is_file():
            raise RuntimeError('Missing PostgreSQL portable executable: ' + name)
    config_path = root / 'config.json'
    if not config_path.exists():
        if (cluster / 'PG_VERSION').exists():
            raise RuntimeError('Existing cluster has no config; restore its config before continuing.')
        password = secrets.token_hex(24)
        config = {
            'database_url': 'postgresql+psycopg://snackup_local:' + password +
                            '@127.0.0.1:55432/snackup_integration',
            'secret_key': secrets.token_hex(32),
            'public_origin': 'http://localhost:18080',
            'media_dir': str(root / 'media'),
            'port': 18080,
        }
        with config_path.open('x', encoding='utf-8') as stream:
            json.dump(config, stream, indent=2)
    config = json.loads(config_path.read_text(encoding='utf-8'))
    uri = urlsplit(config['database_url'])
    if (uri.scheme != 'postgresql+psycopg' or uri.hostname != '127.0.0.1' or
            uri.port != 55432 or uri.username != 'snackup_local' or
            uri.path != '/snackup_integration' or uri.query or uri.fragment or not uri.password):
        raise RuntimeError('Config does not identify the isolated integration database.')
    environment = {k: v for k, v in os.environ.items() if not k.upper().startswith('PG')}
    flags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0

    def run(name, *arguments, check=True):
        # A Windows postgres child can retain pg_ctl's pipe handles after the
        # launcher exits. A file avoids waiting for EOF from a running server.
        with (logs / 'postgres-setup.log').open('ab') as output:
            result = subprocess.run([str(binaries / name), *map(str, arguments)],
                                    env=environment, creationflags=flags,
                                    stdout=output, stderr=subprocess.STDOUT)
        if check and result.returncode:
            # No subprocess output or connection string is exposed on failures.
            raise RuntimeError(name + ' failed; inspect the local PostgreSQL log.')
        return result

    if not (cluster / 'PG_VERSION').exists():
        if cluster.exists() and any(cluster.iterdir()):
            raise RuntimeError('Refusing to initialize a nonempty data directory.')
        cluster.mkdir(exist_ok=True)
        password_file = None
        try:
            with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8',
                                             dir=root, prefix='.pg-password-',
                                             delete=False) as stream:
                password_file = Path(stream.name)
                stream.write(uri.password + '\n')
            run('initdb.exe', '-D', cluster, '-U', uri.username,
                '--encoding=UTF8', '--locale=C', '--auth=scram-sha-256',
                '--pwfile=' + str(password_file))
        finally:
            if password_file is not None:
                password_file.unlink(missing_ok=True)
    if run('pg_ctl.exe', '-D', cluster, 'status', check=False).returncode != 0:
        run('pg_ctl.exe', '-D', cluster, '-l', logs / 'postgres.log',
            '-o', '-h 127.0.0.1 -p 55432', '-w', '-t', '30', 'start')
    admin_url = urlunsplit(uri._replace(scheme='postgresql', path='/postgres'))
    with psycopg.connect(admin_url, autocommit=True, connect_timeout=5) as connection:
        actual = Path(connection.execute('SHOW data_directory').fetchone()[0]).resolve()
        if actual != cluster.resolve():
            raise RuntimeError('The listening database does not belong to this integration cluster.')
        exists = connection.execute('SELECT 1 FROM pg_database WHERE datname = %s',
                                    ('snackup_integration',)).fetchone()
        if not exists:
            connection.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier('snackup_integration')))
    with psycopg.connect(urlunsplit(uri._replace(scheme='postgresql')),
                        connect_timeout=5) as connection:
        version = connection.execute('SHOW server_version').fetchone()[0]
    print(json.dumps({'ready': True, 'postgres_version': version,
                      'host': '127.0.0.1', 'database_port': 55432,
                      'database': 'snackup_integration', 'config': str(config_path),
                      'data_directory': str(cluster)}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # Connection exceptions may contain credentials; report only our own
        # controlled RuntimeError messages or the exception type.
        print(str(error) if isinstance(error, RuntimeError) else type(error).__name__, file=sys.stderr)
        sys.exit(1)
