"""Explicit fake load data in a dedicated database; never runs at app startup."""
import argparse
import json
import os
from pathlib import Path
import secrets
from uuid import uuid4

from sqlalchemy import text
from sqlalchemy.engine import make_url
from sqlalchemy.exc import SQLAlchemyError

from snackup import admin_models, push_models, review_models  # noqa: F401
from snackup.auth import hash_password
from snackup.config import Settings
from snackup.db import Database, new_id
from snackup.identity_models import AcademicGroup, AcademicRecord, Career, User
from snackup.operation_models import Business, Product


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--students', type=int, default=1000)
    parser.add_argument('--businesses', type=int, default=4)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--confirm-isolated', action='store_true', required=True)
    args = parser.parse_args()
    settings = Settings()
    database_name = make_url(settings.database_url).database or ''
    if settings.environment == 'production' or 'loadtest' not in database_name.lower():
        parser.error('Use a dedicated database whose name contains loadtest, with environment=test or development.')
    if not 1 <= args.students <= 1000 or not 1 <= args.businesses <= 20:
        parser.error('Use 1..1000 students and 1..20 test businesses.')
    output = args.output.resolve()
    if output.is_relative_to(Path(__file__).resolve().parents[2]):
        parser.error('The credentials file must be outside the Git repository.')
    if output.exists() or not output.parent.is_dir():
        parser.error('Output must be a new file in an existing private directory.')
    database = Database(settings)
    namespace = uuid4().hex[:10]
    result = {'fixture': namespace, 'students': [], 'operators': [], 'initialProductStock': args.students}
    try:
        with output.open('x', encoding='utf-8') as destination:
            os.chmod(output, 0o600)
            try:
                with database.sessions.begin() as db:
                    db.execute(text('SELECT version_num FROM alembic_version'))
                    career_id, group_id = new_id(), new_id()
                    db.add(Career(id=career_id, name='[CARGA] Carrera ficticia'))
                    db.flush()
                    db.add(AcademicGroup(id=group_id, career_id=career_id, name='[CARGA] Grupo ficticio'))
                    businesses = []
                    for index in range(args.businesses):
                        business_id, product_id = new_id(), new_id()
                        db.add(Business(id=business_id, name=f'[CARGA {namespace}] Local {index + 1}',
                                        cafeteria_id=settings.cafeteria_id, cafeteria_name=settings.cafeteria_name,
                                        is_active=True, is_open=True))
                        db.flush()
                        db.add(Product(id=product_id, business_id=business_id, name='[CARGA] Producto',
                                       category='Prueba', price='10.00', stock=args.students, is_available=True))
                        email = f'operator-{namespace}-{index}@load.snackup.invalid'
                        password = secrets.token_urlsafe(24)
                        db.add(User(email=email, display_name='[CARGA] Operador', password_hash=hash_password(password),
                                    role='business', business_id=business_id, is_active=True,
                                    approval_status='approved', email_verified=True))
                        result['operators'].append({'email': email, 'password': password, 'businessId': business_id})
                        businesses.append((business_id, product_id))
                    db.flush()
                    for index in range(args.students):
                        email = f'student-{namespace}-{index}@load.snackup.invalid'
                        password = secrets.token_urlsafe(24)
                        business_id, product_id = businesses[index % len(businesses)]
                        db.add(User(email=email, display_name='[CARGA] Alumno ficticio', password_hash=hash_password(password),
                                    role='user', is_active=True, approval_status='approved', email_verified=True))
                        db.add(AcademicRecord(email=email, institutional_id=f'LOAD-{namespace}-{index}',
                                              display_name='[CARGA] Alumno ficticio', kind='student', career_id=career_id,
                                              group_id=group_id, source=f'isolated-loadtest:{namespace}'))
                        result['students'].append({'email': email, 'password': password,
                                                   'businessId': business_id, 'productId': product_id})
                    json.dump(result, destination, ensure_ascii=False, indent=2)
            except Exception:
                destination.close()
                output.unlink(missing_ok=True)  # Only the new file created by this invocation.
                raise
        print(f'Created {args.students} fictitious students in isolated loadtest database. Credentials saved privately.')
    except (SQLAlchemyError, OSError):
        raise SystemExit('Fixtures were not confirmed. Check the isolated database, migrations and private output permissions.') from None
    finally:
        database.dispose()


if __name__ == '__main__':
    main()
