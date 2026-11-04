#!/usr/bin/env python3
"""Seed only the private snackup_integration PostgreSQL database after migrations.

python tools/seed_integrated.py --config C:/Users/video/Documents/JC/SnackUP-Integracion-Local/config.json

Uses integrated_server.py configuration validation. Existing records, passwords,
stock and edits are preserved. These are PUBLIC SYNTHETIC credentials only:
master@staff.example.edu / operator@staff.example.edu / alumno.demo@utsjr.edu.mx
Password for newly created accounts: SnackUP-Prueba-V32!
No migrations, schema creation, reset, or remote environment configuration.
"""
from __future__ import annotations

import argparse
from decimal import Decimal
from pathlib import Path
import sys

from integrated_server import configuration, local_settings, DEFAULT_CONFIG


def seed(config):
    from sqlalchemy import select
    from snackup.auth import hash_password
    from snackup.db import Database, utcnow
    from snackup.identity_models import AcademicGroup, AcademicRecord, Career, User
    from snackup.operation_models import Business, Product
    # Import all model tables referenced by relationships without creating an
    # application, threads, SQL schema or an event bridge.
    from snackup import admin_models, review_models, v32_models, push_models  # noqa: F401

    database = Database(local_settings(config))
    inserted = []
    try:
        with database.sessions.begin() as db:
            # Prevent two concurrent invocations from racing on synthetic IDs.
            from sqlalchemy import text
            db.execute(text('SELECT pg_advisory_xact_lock(73180420)'))

            def ensure(model, identity, **values):
                existing = db.get(model, identity)
                if existing is None:
                    db.add(model(id=identity, **values))
                    db.flush()
                    inserted.append(model.__tablename__ + ':' + identity)

            ensure(Career, 'integration-career', name='Desarrollo de Software (prueba)')
            ensure(AcademicGroup, 'integration-group', career_id='integration-career', name='DEMO-1')
            ensure(Business, 'integration-local', name='Cafetería de integración',
                   category='Comida y bebidas', description='Datos ficticios para pruebas locales.',
                   cafeteria_id='integration-cafeteria', cafeteria_name='Cafetería de prueba',
                   is_open=True, is_active=True)
            accounts = [
                ('integration-master', 'master@staff.example.edu', 'Cuenta maestra de prueba', 'admin', None, True),
                ('integration-operator', 'operator@staff.example.edu', 'Cocina de prueba', 'business', 'integration-local', False),
                ('integration-student', 'alumno.demo@utsjr.edu.mx', 'Alumno de prueba', 'user', None, False),
            ]
            password = None
            for identity, email, name, role, business, master in accounts:
                existing = db.scalar(select(User).where(User.email == email))
                if existing is not None or db.get(User, identity) is not None:
                    continue  # Never replace a password, role or existing account.
                if password is None:
                    password = hash_password('SnackUP-Prueba-V32!')
                ensure(User, identity, email=email, display_name=name, role=role,
                       business_id=business, is_master=master, is_active=True,
                       email_verified=True, approval_status='approved', password_hash=password,
                       numero_de_control='DEMO-001' if role == 'user' else None,
                       institutional_verified_at=utcnow() if role == 'user' else None)
            record = db.scalar(select(AcademicRecord).where(
                AcademicRecord.email == 'alumno.demo@utsjr.edu.mx'))
            if record is None:
                ensure(AcademicRecord, 'integration-roster', email='alumno.demo@utsjr.edu.mx',
                       institutional_id='DEMO-001', display_name='Alumno de prueba', kind='student',
                       career_id='integration-career', group_id='integration-group',
                       is_active=True, source='synthetic local integration')
            for identity, name, category, price in [
                ('integration-torta', 'Torta de pollo', 'Comida', '35.50'),
                ('integration-agua', 'Agua de jamaica', 'Bebidas', '18.00'),
                ('integration-sandwich', 'Sándwich integral', 'Comida', '42.00'),
            ]:
                ensure(Product, identity, business_id='integration-local', name=name,
                       category=category, price=Decimal(price), stock=30, is_available=True,
                       manual_available=True, is_featured=True)
        return inserted
    finally:
        database.dispose()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=DEFAULT_CONFIG)
    args = parser.parse_args()
    try:
        inserted = seed(configuration(args.config))
        print('Synthetic seed completed: ' + str(len(inserted)) + ' new records; existing data preserved.')
    except Exception as error:
        print('Synthetic seed failed: ' + type(error).__name__ + '. No credentials are logged.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
