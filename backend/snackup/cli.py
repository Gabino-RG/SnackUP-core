"""Private administration, run on the server by an authorized operator.

No HTTP bootstrap route, default password, public seed or implicit migration.
Passwords are read without echo and never accepted as command-line arguments.
"""
import argparse
from getpass import getpass
import json
from pathlib import Path
import sys

from sqlalchemy import select, text
from sqlalchemy.exc import SQLAlchemyError

from . import admin_models, operation_models  # noqa: F401 -- register schema
from .auth import hash_password, revoke_user_sessions
from .config import Settings
from .db import Database
from .errors import ApiError
from .identity import import_roster_csv, normalize_email
from .identity_models import User


def _password():
    password = getpass('Contraseña nueva (12–128 caracteres): ')
    if password != getpass('Repite la contraseña: '):
        raise ValueError('Las contraseñas no coinciden.')
    return hash_password(password)


def _master_lock(db):
    # All private bootstrap/recovery commands serialize on the same PG lock.
    if db.bind.dialect.name == 'postgresql':
        db.execute(text('SELECT pg_advisory_xact_lock(734210819)'))


def main(argv=None, settings=None):
    parser = argparse.ArgumentParser(description='Administración privada de SnackUP; ejecutar desde backend/.')
    commands = parser.add_subparsers(dest='command', required=True)
    create = commands.add_parser('create-master', help='Crear el primer maestro, sin cuentas de ejemplo.')
    create.add_argument('--email', required=True)
    create.add_argument('--name', required=True)
    reset = commands.add_parser('reset-master-password', help='Recuperar un maestro existente y revocar sus sesiones.')
    reset.add_argument('--email', required=True)
    roster = commands.add_parser('import-roster', help='Importar un padrón CSV autorizado de forma atómica.')
    roster.add_argument('file', type=Path)
    roster.add_argument('--source', required=True, help='Identificador de procedencia del padrón autorizado.')
    roster.add_argument('--dry-run', action='store_true', help='Validar el CSV y revertir todos sus cambios.')
    args = parser.parse_args(argv)
    database = None
    try:
        settings = settings or Settings()
        database = Database(settings)
        if args.command == 'import-roster':
            if not args.file.is_file() or args.file.stat().st_size > 10 * 1024 * 1024:
                raise ValueError('El CSV debe existir y no superar 10 MiB.')
            content = args.file.read_text(encoding='utf-8-sig')
            with database.sessions() as db:
                with db.begin():
                    # sqlite3 legacy transaction control otherwise releases an
                    # initial SAVEPOINT as a commit, defeating dry-run rollback.
                    if database.engine.dialect.name == 'sqlite':
                        db.connection().exec_driver_sql('BEGIN IMMEDIATE')
                    result = import_roster_csv(db, content, args.source)
                    if args.dry_run:
                        db.rollback()
                print(json.dumps({'dryRun': args.dry_run, **result}, ensure_ascii=False))
        else:
            email = normalize_email(args.email)
            if args.command == 'create-master':
                domains = {part.strip().lower() for part in settings.admin_email_domains.split(',') if part.strip()}
                if email.rsplit('@', 1)[1] not in domains:
                    raise ValueError('El correo debe pertenecer a SNACKUP_ADMIN_EMAIL_DOMAINS.')
                if not 1 <= len(args.name.strip()) <= 100:
                    raise ValueError('El nombre debe tener entre 1 y 100 caracteres.')
            encoded = _password()
            with database.sessions.begin() as db:
                _master_lock(db)
                if args.command == 'create-master':
                    if db.scalar(select(User.id).where(User.is_master.is_(True)).limit(1)):
                        raise ValueError('Ya existe un maestro; utiliza recuperación para la cuenta existente.')
                    if db.scalar(select(User.id).where(User.email == email)):
                        raise ValueError('Ese correo ya tiene cuenta; no se sobrescribió ni se elevó su rol.')
                    user = User(email=email, display_name=args.name.strip(), password_hash=encoded,
                                role='admin', is_master=True, is_active=True,
                                approval_status='approved', email_verified=True)
                    db.add(user)
                    db.flush()
                    result = {'action': 'masterCreated', 'id': user.id, 'email': user.email}
                else:
                    user = db.scalar(select(User).where(User.email == email, User.is_master.is_(True))
                                     .with_for_update())
                    if user is None:
                        raise ValueError('No existe un maestro con ese correo.')
                    user.password_hash = encoded
                    user.version += 1
                    revoke_user_sessions(db, user)
                    result = {'action': 'masterPasswordReset', 'id': user.id, 'sessionsRevoked': True}
            print(json.dumps(result, ensure_ascii=False))
        return 0
    except ApiError as error:
        print(error.message if hasattr(error, 'message') else error.payload()['error']['message'], file=sys.stderr)
    except (ValueError, OSError) as error:
        # Pydantic settings validation can contain input secrets. Never print it.
        from pydantic import ValidationError
        print('Configuración inválida: revisa las variables SNACKUP_*.' if isinstance(error, ValidationError)
              else str(error), file=sys.stderr)
    except SQLAlchemyError:
        print('No se confirmó la operación SQL. Revisa conexión, migraciones y conflictos; no se muestran credenciales.', file=sys.stderr)
    finally:
        if database:
            database.dispose()
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
