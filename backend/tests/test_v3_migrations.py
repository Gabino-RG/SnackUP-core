"""Exercise Alembic against populated V1 databases, not metadata.create_all()."""
from datetime import datetime, timezone
from decimal import Decimal
import os
from pathlib import Path
from urllib.parse import quote
from uuid import uuid4

from alembic import command
from alembic.config import Config
import pytest
import sqlalchemy as sa
from sqlalchemy.exc import IntegrityError


ROOT = Path(__file__).resolve().parents[1]
STAMP = datetime(2026, 1, 2, 12, 30, tzinfo=timezone.utc)
pytestmark = pytest.mark.v3


@pytest.fixture(params=['sqlite', 'postgres'])
def migrated_database(request, tmp_path, monkeypatch):
    admin_engine = None
    schema = None
    if request.param == 'postgres':
        base = os.environ.get('SNACKUP_TEST_DATABASE_URL')
        if not base:
            pytest.skip('Set SNACKUP_TEST_DATABASE_URL to exercise PostgreSQL migration.')
        admin_engine = sa.create_engine(base)
        schema = 'migration_' + uuid4().hex
        with admin_engine.begin() as connection:
            connection.execute(sa.text(f'CREATE SCHEMA "{schema}"'))
        url = base + ('&' if '?' in base else '?') + 'options=' + quote('-c search_path=' + schema)
    else:
        url = 'sqlite:///' + (tmp_path / 'migration.db').as_posix()
    monkeypatch.setenv('SNACKUP_DATABASE_URL', url)
    monkeypatch.setenv('SNACKUP_SECRET_KEY', 'migration-test-' + uuid4().hex)
    monkeypatch.setenv('SNACKUP_ENVIRONMENT', 'test')
    config = Config(str(ROOT / 'alembic.ini'))
    engine = sa.create_engine(url)
    try:
        command.upgrade(config, '0001_initial')
        yield engine, config
    finally:
        engine.dispose()
        if schema:
            with admin_engine.begin() as connection:
                connection.execute(sa.text(f'DROP SCHEMA "{schema}" CASCADE'))
            admin_engine.dispose()


def _seed_v1(engine):
    metadata = sa.MetaData()
    metadata.reflect(bind=engine)

    def insert(connection, table_name, **values):
        table = metadata.tables[table_name]
        row = {}
        for column in table.columns:
            if column.name in values:
                row[column.name] = values[column.name]
            elif column.nullable:
                row[column.name] = None
            elif isinstance(column.type, sa.Boolean):
                row[column.name] = False
            elif isinstance(column.type, sa.Integer):
                row[column.name] = 1
            elif isinstance(column.type, sa.Numeric):
                row[column.name] = Decimal('35.50')
            elif isinstance(column.type, sa.DateTime):
                row[column.name] = STAMP
            elif isinstance(column.type, sa.JSON):
                row[column.name] = {}
            else:
                row[column.name] = 'historic'
        connection.execute(table.insert().values(**row))

    with engine.begin() as connection:
        insert(connection, 'businesses', id='firestore-business', name='Cafetería histórica',
               is_active=True, is_open=True, next_order_number=4, timezone='America/Mexico_City')
        insert(connection, 'careers', id='career-history', name='Carrera histórica', is_active=True)
        insert(connection, 'academic_groups', id='group-history', career_id='career-history', is_active=True)
        for user_id, role, email, business_id in [
            ('student-history', 'user', 'historic@students.example.edu', None),
            ('operator-history', 'business', 'historic@staff.example.edu', 'firestore-business'),
            ('master-history', 'admin', 'master@staff.example.edu', None),
        ]:
            insert(connection, 'users', id=user_id, role=role, email=email, business_id=business_id,
                   password_hash='historic-password-hash-must-not-change', is_active=True,
                   is_master=role == 'admin', email_verified=True, approval_status='approved')
        insert(connection, 'academic_records', id='roster-history', email='historic@students.example.edu',
               institutional_id='CONTROL-HISTORICO', kind='student', career_id='career-history',
               group_id='group-history', is_active=True, source='authorized-test-fixture')
        insert(connection, 'access_requests', id='request-history', user_id='operator-history',
               reviewed_by='master-history', requested_role='business', approval_status='approved',
               email_verified=True, provider='email')
        insert(connection, 'access_decisions', id='decision-history', request_id='request-history',
               user_id='operator-history', actor_id='master-history', decision='approved',
               role='business', business_id='firestore-business')
        insert(connection, 'products', id='firestore-product', business_id='firestore-business',
               name='Producto histórico', stock=0, is_available=False)
        insert(connection, 'media_files', id='media-history', business_id='firestore-business',
               filename='historical-image.webp', mime_type='image/webp', size=1234)
        for number, status in enumerate(['completed', 'pending', 'cancelled'], start=1):
            order_id = 'order-' + status
            extra = {'completed_at': STAMP, 'verification_method': 'manual',
                     'verified_by': 'operator-history'} if status == 'completed' else {}
            if status == 'cancelled':
                extra = {'cancelled_at': STAMP, 'cancelled_by': 'student-history',
                         'cancel_reason': 'user_other', 'cancel_notes': 'Historic cancellation',
                         'stock_restored': True}
            insert(connection, 'orders', id=order_id, business_id='firestore-business',
                   student_id='student-history', order_number=number, status=status,
                   customer_name='Nombre al comprar', payment_method='cash', payment_status='pay_at_pickup',
                   pickup_code='12345678', **extra)
            insert(connection, 'order_items', id='item-' + status, order_id=order_id,
                   product_id='firestore-product', name='Nombre original', quantity=1, reserved_quantity=1)
            insert(connection, 'order_transitions', id='transition-' + status, order_id=order_id,
                   actor_id='student-history', to_status=status)
        insert(connection, 'idempotency_records', id='idempotency-history', user_id='student-history',
               key='historic-idempotency-key', payload_hash='a' * 64, order_id='order-pending',
               response_json={'id': 'order-pending', 'pickupCode': '12345678', 'version': 1})
        insert(connection, 'refresh_sessions', id='refresh-history', user_id='student-history',
               family_id='family-history', token_hash='b' * 64)
        insert(connection, 'verification_tokens', id='verification-history', user_id='student-history',
               purpose='reset', token_hash='c' * 64)
        insert(connection, 'reviews', id='review-history', order_id='order-completed',
               user_id='student-history', business_id='firestore-business', rating=4,
               career_id='career-history', group_id='group-history', career_name='Carrera al opinar',
               group_name='Grupo al opinar', comment='Opinión histórica que debe conservarse.')
        insert(connection, 'followups', review_id='review-history', business_id='firestore-business',
               status='in_review', note='Seguimiento histórico')
        insert(connection, 'followup_events', id='followup-event-history', review_id='review-history',
               business_id='firestore-business', actor_id='master-history', status='in_review')
        insert(connection, 'outbox_events', id=1, event_id='d' * 32, topic='user.student-history',
               event_type='order.updated', data={'id': 'order-pending', 'version': 1})
    return metadata


def _snapshot(engine, metadata):
    with engine.connect() as connection:
        return {name: [dict(row) for row in connection.execute(sa.select(table).order_by(*table.primary_key)).mappings()]
                for name, table in metadata.tables.items() if name != 'alembic_version'}


def test_populated_v1_upgrade_preserves_all_historical_columns_and_constraints(migrated_database):
    engine, config = migrated_database
    old = _seed_v1(engine)
    before = _snapshot(engine, old)
    command.upgrade(config, 'head')
    assert _snapshot(engine, old) == before
    command.check(config)
    current = sa.MetaData()
    current.reflect(bind=engine)
    assert {'devices', 'push_deliveries', 'product_reviews', 'account_audit_events'} <= current.tables.keys()
    inspector = sa.inspect(engine)
    assert isinstance(next(c['type'] for c in inspector.get_columns('orders') if c['name'] == 'id'), sa.Text)
    assert any(index['name'] == 'uq_orders_v3_pickup_code' and index['unique']
               for index in inspector.get_indexes('orders'))
    assert any(index['name'] == 'uq_active_business_operator' and index['unique']
               for index in inspector.get_indexes('users'))
    with engine.connect() as connection:
        user = connection.execute(sa.select(current.tables['users']).where(
            current.tables['users'].c.id == 'student-history')).mappings().one()
        assert user['numero_de_control'] == 'CONTROL-HISTORICO'
        assert user['institutional_verified_at'] is None and user['last_login_at'] is None
        product = connection.execute(sa.select(current.tables['products'])).mappings().one()
        assert product['manual_available'] is False and product['stock'] == 0
        assert product['deleted_at'] is None
        media = connection.execute(sa.select(current.tables['media_files'])).mappings().one()
        assert media['purpose'] == 'product' and media['owner_id'] is None
        for order in connection.execute(sa.select(current.tables['orders'])).mappings():
            assert order['subtotal'] == order['total']
            assert order['customer_institutional_id'] is None
            assert order['pickup_code'] == '12345678'
            if order['status'] == 'completed':
                assert order['verified_at'] == order['completed_at']
            if order['status'] == 'cancelled':
                assert order['cancelled_by_role'] == 'ALUMNO'
        review = connection.execute(sa.select(current.tables['reviews'])).mappings().one()
        assert review['updated_at'] == review['created_at']
        idempotency = connection.execute(sa.select(current.tables['idempotency_records'])).mappings().one()
        assert idempotency['updated_at'] == idempotency['created_at'] and idempotency['expires_at'] is None
        assert connection.execute(sa.select(current.tables['outbox_events'].c.publish_attempts)).scalar_one() == 0
        if engine.dialect.name == 'sqlite':
            assert connection.exec_driver_sql('PRAGMA foreign_key_check').all() == []
    # These checks were unnamed in 0001: SQLite's batch recreation must retain them.
    for table, values in [('products', {'stock': -1}), ('products', {'is_available': True}),
                          ('products', {'preparation_minutes': -1}), ('products', {'calories': -1}),
                          ('businesses', {'version': 0}), ('orders', {'status': 'made_up'}),
                          ('order_items', {'reserved_quantity': 2})]:
        with pytest.raises(IntegrityError), engine.begin() as connection:
            connection.execute(current.tables[table].update().values(**values))
    # The new uniqueness gate applies only to six-character codes, so old duplicates survive.
    with engine.begin() as connection:
        connection.execute(current.tables['orders'].update().where(
            current.tables['orders'].c.id == 'order-pending').values(pickup_code='A7X9B2'))
    with pytest.raises(IntegrityError), engine.begin() as connection:
        connection.execute(current.tables['orders'].update().where(
            current.tables['orders'].c.id == 'order-completed').values(pickup_code='A7X9B2'))
    # Rollback must not erase V3 data or silently shrink opaque IDs.
    with pytest.raises(RuntimeError, match='verified pre-upgrade'):
        command.downgrade(config, '0001_initial')
    with engine.connect() as connection:
        assert connection.execute(sa.text('SELECT version_num FROM alembic_version')).scalar_one() == '0002_v3'
