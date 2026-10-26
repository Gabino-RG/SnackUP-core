"""Private PostgreSQL cluster for SnackUP, using installed PostgreSQL binaries."""
import argparse
import json
import os
from pathlib import Path
import secrets
import subprocess

from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / '.local' / 'snackup-demo'
CONFIG = PRIVATE / 'postgresql.json'


def run(command):
    return subprocess.run([str(value) for value in command], check=True,
                          creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))


def url(config, database=None):
    return URL.create('postgresql+psycopg', username=config['user'], password=config['password'],
                      host='127.0.0.1', port=config['port'], database=database or config['database'])


def load():
    return json.loads(CONFIG.read_text(encoding='utf-8'))


def ensure_server():
    PRIVATE.mkdir(parents=True, exist_ok=True)
    if CONFIG.exists():
        config = load()
    else:
        binaries = next((Path(os.environ.get('ProgramFiles', 'C:/Program Files')) / 'PostgreSQL' / version / 'bin'
                         for version in ['18', '17', '16']
                         if (Path(os.environ.get('ProgramFiles', 'C:/Program Files')) / 'PostgreSQL' / version / 'bin/initdb.exe').exists()), None)
        if binaries is None:
            raise RuntimeError('No se encontraron los ejecutables de PostgreSQL 16 o posterior.')
        config = {'engine': 'postgresql', 'user': 'snackup_local', 'password': secrets.token_urlsafe(32),
                  'port': 55432, 'database': 'snackup_local', 'bin': str(binaries)}
        # Save the generated credential before initializing so retries keep it.
        CONFIG.write_text(json.dumps(config, indent=2), encoding='utf-8')
    data = PRIVATE / 'postgres-data'
    binary = Path(config['bin'])
    if not (data / 'PG_VERSION').exists():
        password_file = PRIVATE / 'postgres-init-password.txt'
        password_file.write_text(config['password'], encoding='utf-8')
        try:
            run([binary / 'initdb.exe', '-D', data, '-U', config['user'], '--auth=scram-sha-256',
                 '--encoding=UTF8', '--locale=C', '--pwfile', password_file])
        finally:
            password_file.unlink(missing_ok=True)
    status = subprocess.run([str(binary / 'pg_ctl.exe'), '-D', str(data), 'status'],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    if status.returncode:
        run([binary / 'pg_ctl.exe', '-D', data, '-l', PRIVATE / 'postgres.log',
             '-o', '-h 127.0.0.1 -p ' + str(config['port']), '-w', 'start'])
    engine = create_engine(url(config, 'postgres'), isolation_level='AUTOCOMMIT', connect_args={'connect_timeout': 5})
    try:
        with engine.connect() as connection:
            actual = Path(connection.scalar(text('SHOW data_directory'))).resolve()
            if actual != data.resolve():
                raise RuntimeError('El puerto pertenece a otra instancia. No se modifico esa instancia.')
            if not connection.scalar(text("SELECT 1 FROM pg_database WHERE datname = 'snackup_local'")):
                connection.execute(text('CREATE DATABASE snackup_local'))
    finally:
        engine.dispose()
    return config


def setup():
    config = ensure_server()
    (PRIVATE / 'database.json').write_text(json.dumps({'engine': 'postgresql'}), encoding='utf-8')
    print('PostgreSQL local listo: 127.0.0.1:' + str(config['port']) + ' / snackup_local')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--stop', action='store_true')
    args = parser.parse_args()
    if args.stop:
        config = load()
        run([Path(config['bin']) / 'pg_ctl.exe', '-D', PRIVATE / 'postgres-data', '-m', 'fast', '-w', 'stop'])
    else:
        setup()
