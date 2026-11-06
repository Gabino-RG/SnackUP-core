"""Back up the existing Windows integration database and verify an isolated restore."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid
import zipfile
from urllib.parse import urlsplit

import psycopg
from psycopg import sql

from setup_local_postgres import DEFAULT_ROOT


def private_directory(root, name):
    path = root / name
    path.mkdir(exist_ok=False)
    # Restrict the new empty directory before writing database or media data.
    system = Path(os.environ['SystemRoot']) / 'System32'
    identity = subprocess.check_output([str(system / 'whoami.exe'), '/user', '/fo', 'csv', '/nh'])
    sid = next(csv.reader([identity.decode('ascii', errors='replace').strip()]))[1]
    subprocess.run([str(system / 'icacls.exe'), str(path), '/inheritance:r', '/grant:r',
                    f'*{sid}:(OI)(CI)F', '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F'],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return path


def table_fingerprints(connection):
    connection.execute("SET LOCAL TIME ZONE 'UTC'")
    result = {}
    tables = connection.execute(
        "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename"
    ).fetchall()
    for (name,) in tables:
        # Hash complete rows in the database. Compare sorted hashes, including duplicates.
        rows = connection.execute(sql.SQL(
            "SELECT sha256(convert_to(to_jsonb(t)::text, 'UTF8')) AS row_hash "
            "FROM {} AS t ORDER BY row_hash"
        ).format(sql.Identifier('public', name)))
        digest = hashlib.sha256()
        count = 0
        for (fingerprint,) in rows:
            digest.update(fingerprint)
            count += 1
        result[name] = (count, digest.digest())
    return result


def verify_media(media, destination):
    recovered = destination / 'media-restored'
    recovered.mkdir()
    archive = destination / 'media.zip'
    fingerprints = {}
    with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_DEFLATED) as target:
        for path in sorted(media.rglob('*')):
            if path.is_symlink() or path.is_junction() or not path.resolve().is_relative_to(media):
                raise RuntimeError('Media contains a link outside the expected tree.')
            if path.is_file():
                name = path.relative_to(media).as_posix()
                with path.open('rb') as source, target.open(name, 'w') as member:
                    digest = hashlib.sha256()
                    while chunk := source.read(1 << 20):
                        digest.update(chunk)
                        member.write(chunk)
                fingerprints[name] = digest.digest()
    with zipfile.ZipFile(archive) as target:
        if set(target.namelist()) != set(fingerprints):
            raise RuntimeError('Media inventory mismatch.')
        for name, expected in fingerprints.items():
            path = Path(target.extract(name, recovered))
            with path.open('rb') as restored:
                if hashlib.file_digest(restored, 'sha256').digest() != expected:
                    raise RuntimeError('Media verification failed.')
    return len(fingerprints)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=DEFAULT_ROOT)
    args = parser.parse_args()
    root = args.root.resolve()
    checkout = Path(__file__).resolve().parents[1]
    if os.name != 'nt' or root.is_relative_to(checkout):
        raise RuntimeError('Use the external Windows integration directory.')
    config = json.loads((root / 'config.json').read_text(encoding='utf-8-sig'))
    uri = urlsplit(config['database_url'])
    source_name = 'snackup_integration'
    if (uri.scheme != 'postgresql+psycopg' or uri.hostname != '127.0.0.1' or uri.port != 55432
            or uri.username != 'snackup_local' or uri.path != '/' + source_name
            or not uri.password or uri.query or uri.fragment):
        raise RuntimeError('Config does not identify the local integration PostgreSQL.')
    media = Path(config['media_dir']).resolve(strict=True)
    if media != root / 'media':
        raise RuntimeError('Unexpected media directory.')
    kwargs = dict(host=uri.hostname, port=uri.port, user=uri.username, password=uri.password,
                  connect_timeout=5)
    binaries = root / 'runtime/pgsql/bin'
    environment = {key: value for key, value in os.environ.items() if not key.upper().startswith('PG')}
    environment.update(PGHOST=uri.hostname, PGPORT=str(uri.port), PGUSER=uri.username, PGPASSWORD=uri.password)

    def run(tool, *arguments):
        subprocess.run([str(binaries / tool), *map(str, arguments)], check=True,
                       env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       creationflags=subprocess.CREATE_NO_WINDOW)

    tag = uuid.uuid4().hex
    temporary_name = 'snackup_restore_' + tag
    with psycopg.connect(dbname='postgres', autocommit=True, **kwargs) as admin:
        if Path(admin.execute('SHOW data_directory').fetchone()[0]).resolve() != root / 'postgres-data':
            raise RuntimeError('The listener belongs to another cluster.')
        destination = private_directory(root, 'backup-' + tag)
        dump = destination / 'database.dump'
        with psycopg.connect(dbname=source_name, **kwargs) as original:
            original.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY')
            snapshot = original.execute('SELECT pg_export_snapshot()').fetchone()[0]
            run('pg_dump.exe', '--format=custom', '--no-password', '--file', dump,
                '--snapshot', snapshot, '--dbname', source_name)
            expected = table_fingerprints(original)
            revision = original.execute('SELECT version_num FROM alembic_version').fetchone()[0]
        restored_db = sql.Identifier(temporary_name)
        admin.execute(sql.SQL('CREATE DATABASE {} TEMPLATE template0').format(restored_db))
        try:
            admin.execute(sql.SQL('REVOKE ALL ON DATABASE {} FROM PUBLIC').format(restored_db))
            run('pg_restore.exe', '--exit-on-error', '--single-transaction', '--no-owner', '--no-password',
                '--dbname', temporary_name, dump)
            with psycopg.connect(dbname=temporary_name, **kwargs) as restored:
                restored.execute('SET TRANSACTION READ ONLY')
                if expected != table_fingerprints(restored):
                    raise RuntimeError('Restored database differs from the snapshot.')
        finally:
            # CREATE above succeeded. The name is generated for this run and cannot select the source.
            admin.execute(sql.SQL('DROP DATABASE {}').format(restored_db))
        version = admin.execute('SHOW server_version').fetchone()[0]
    media_files = verify_media(media, destination)
    for artifact in (dump, destination / 'media.zip'):
        with artifact.open('rb') as stream:
            checksum = hashlib.file_digest(stream, 'sha256').hexdigest()
        artifact.with_suffix(artifact.suffix + '.sha256').write_text(
            checksum + '  ' + artifact.name + '\n', encoding='ascii')
    print(json.dumps({'verified': True, 'postgres': version, 'migration': revision,
                      'tables': len(expected), 'rows': sum(count for count, _ in expected.values()),
                      'mediaFiles': media_files, 'backupDirectory': str(destination)}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # DSNs, backend rows, file names and provider tokens must not appear in diagnostic output.
        print('Restore check failed: ' + (str(error) if type(error) is RuntimeError else type(error).__name__),
              file=sys.stderr)
        sys.exit(1)
