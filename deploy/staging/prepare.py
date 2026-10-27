"""Package the approved backend and pinned panel context; never deploy or create secrets."""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
BACKEND = '81c76c5eda9ba6315fbf1dcd1a69599f8906db5e'
PANELS = '0287cbf7b6fb1a354f2344a8cea75d3fabea1392'
USERS = 'a00d0bf4ecdae74a89f3afbe8ec3d0758efb8884'
REMOTE = 'https://github.com/Gabino-RG/SnackUP-core.git'


def prepare(output: Path, repository: Path = ROOT):
    output = output.resolve()
    archive_path = output.with_suffix('.zip')
    if output.exists() or archive_path.exists():
        raise ValueError('El destino o su ZIP ya existe; elige otro nombre. No se sobrescribió nada.')
    for revision in (BACKEND, PANELS, USERS):
        subprocess.run(['git', '-C', str(repository), 'cat-file', '-e', revision + '^{commit}'], check=True)
    archive = subprocess.check_output(['git', '-C', str(repository), 'archive', '--format=tar', BACKEND, 'backend'])
    with tarfile.open(fileobj=io.BytesIO(archive)) as source:
        members = source.getmembers()
        for member in members:
            name = PurePosixPath(member.name)
            if name.is_absolute() or '..' in name.parts or name.parts[0] != 'backend' or not (member.isdir() or member.isfile()):
                raise ValueError('Tipo o ruta no admitida en el archivo Git')
        output.mkdir(parents=True)
        for member in members:
            target = output.joinpath(*PurePosixPath(member.name).parts)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(source.extractfile(member).read())
                target.chmod(member.mode & 0o777)
    backend = output / 'backend'
    # Compose remains upstream's exact file; explicit contexts select this delivery.
    template = (backend / 'deploy/unified/env.example').read_text(encoding='utf-8')
    clear = {'SNACKUP_DOMAIN', 'TLS_ACME_EMAIL', 'SNACKUP_INSTITUTION_ID', 'SNACKUP_INSTITUTION_NAME',
             'SNACKUP_CAFETERIA_ID', 'SNACKUP_CAFETERIA_NAME', 'SNACKUP_ADMIN_EMAIL_DOMAINS', 'SNACKUP_STUDENT_EMAIL_DOMAINS'}
    lines = [line.split('=', 1)[0] + '=' if line.split('=', 1)[0] in clear else line for line in template.splitlines()]
    lines += ['', '# Revisiones de esta entrega; no sustituir por una rama flotante.',
              f'SNACKUP_PANELS_CONTEXT={REMOTE}#{PANELS}', f'SNACKUP_USERS_CONTEXT={REMOTE}#{USERS}']
    (backend / '.env.example').write_text('\n'.join(lines) + '\n', encoding='utf-8', newline='\n')
    shutil.copyfile(Path(__file__).with_name('configure.py'), backend / 'configure.py')
    shutil.copyfile(Path(__file__).with_name('README.md'), output / 'LEEME.md')
    (output / 'versions.json').write_text(json.dumps({'backend': BACKEND, 'panels': PANELS, 'users': USERS,
        'usersStorage': 'Firebase; not certified for SQL integration', 'purpose': 'staging',
        'containsSecrets': False}, indent=2) + '\n', encoding='utf-8', newline='\n')
    files = sorted(p for p in output.rglob('*') if p.is_file())
    sums = ''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.relative_to(output).as_posix() + '\n' for p in files)
    (output / 'SHA256SUMS').write_text(sums, encoding='utf-8', newline='\n')
    with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED) as result:
        for path in sorted(output.rglob('*')):
            if path.is_file():
                result.write(path, path.relative_to(output).as_posix())
    return archive_path


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(prepare(args.output))
