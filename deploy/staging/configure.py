"""Initialize private server configuration without displaying secrets or starting services."""
import argparse
import os
from pathlib import Path
import re
import secrets

SECRETS = ('POSTGRES_PASSWORD', 'SNACKUP_DB_PASSWORD', 'SNACKUP_SECRET_KEY')
REQUIRED = ('SNACKUP_DOMAIN', 'TLS_ACME_EMAIL', 'SNACKUP_INSTITUTION_ID', 'SNACKUP_INSTITUTION_NAME',
            'SNACKUP_CAFETERIA_ID', 'SNACKUP_CAFETERIA_NAME', 'SNACKUP_ADMIN_EMAIL_DOMAINS',
            'SNACKUP_PANELS_CONTEXT', 'SNACKUP_USERS_CONTEXT') + SECRETS


def initialize(root: Path):
    lines = (root / '.env.example').read_text(encoding='utf-8').splitlines()
    lines = [line.split('=', 1)[0] + '=' + secrets.token_hex(32)
             if line.split('=', 1)[0] in SECRETS else line for line in lines]
    # Exclusive creation: never rotate credentials of an existing database by accident.
    fd = os.open(root / '.env', os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as target:
        target.write('\n'.join(lines) + '\n')


def check(root: Path):
    values = {}
    for line in (root / '.env').read_text(encoding='utf-8').splitlines():
        if line.strip() and not line.lstrip().startswith('#') and '=' in line:
            key, value = line.split('=', 1)
            values[key.strip()] = value.strip().strip('\"\'')
    errors = ['Falta ' + key for key in REQUIRED if not values.get(key)]
    for key in SECRETS:
        if values.get(key) and not re.fullmatch(r'[a-f0-9]{64}', values[key]):
            errors.append(key + ': conservar el secreto hexadecimal generado (64 caracteres).')
    if len({values.get(key) for key in SECRETS}) != len(SECRETS):
        errors.append('Cada secreto debe ser diferente.')
    domain = values.get('SNACKUP_DOMAIN', '')
    if domain and (not re.fullmatch(r'(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}', domain)
                   or domain.lower().endswith(('.test', '.invalid', '.localhost', '.example.edu', '.example.com'))
                   or domain.lower() in ('example.com', 'example.edu')):
        errors.append('SNACKUP_DOMAIN: indicar el dominio real, sin esquema, ruta ni puerto.')
    if values.get('TLS_ACME_EMAIL') and not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', values['TLS_ACME_EMAIL']):
        errors.append('TLS_ACME_EMAIL: indicar un correo de contacto válido.')
    for key in ('SNACKUP_PANELS_CONTEXT', 'SNACKUP_USERS_CONTEXT'):
        if values.get(key) and not re.fullmatch(r'https://github.com/Gabino-RG/SnackUP-core\.git#[a-f0-9]{40}', values[key]):
            errors.append(key + ': conservar una referencia Git completa de 40 caracteres.')
    return errors


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['init', 'check'])
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    if args.action == 'init':
        try:
            initialize(root)
        except FileExistsError:
            parser.exit(1, '.env ya existe; no se modificó.\n')
        print('.env creado con secretos independientes. Completa los campos vacíos en el servidor; no compartas este archivo.')
    else:
        if not (root / '.env').is_file():
            parser.exit(1, 'Primero ejecuta configure.py init.\n')
        errors = check(root)
        if errors:
            parser.exit(1, '\n'.join(errors) + '\n')
        print('Campos básicos completos. Ejecuta también docker compose config --quiet. Esto no prueba DNS, SMTP ni conectividad.')
