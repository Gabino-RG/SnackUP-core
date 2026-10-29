"""V3 FastAPI schema; preserves IDs, credentials, opinions and pickup codes.

Revision ID: 0002_v3
Revises: 0001_initial

The ORM remains SQLAlchemy. Prisma is a descriptive map, never a second
migration authority. Run with application writes paused after a verified backup.
Legacy unavailability is conservatively treated as an operator pause because the
old schema cannot prove whether a false value was manual or stock-generated.
"""
from alembic import op
import sqlalchemy as sa

revision = '0002_v3'
down_revision = '0001_initial'
branch_labels = None
depends_on = None

# Explicit, frozen lists: migrations must not import evolving runtime models.
ID_COLUMNS = {
    'academic_groups': ('id', 'career_id'),
    'academic_records': ('id', 'career_id', 'group_id'),
    'access_decisions': ('id', 'request_id', 'user_id', 'actor_id', 'business_id'),
    'access_requests': ('id', 'user_id', 'reviewed_by'),
    'businesses': ('id',), 'careers': ('id',),
    'followup_events': ('id', 'review_id', 'business_id', 'actor_id'),
    'followups': ('review_id', 'business_id'),
    'idempotency_records': ('id', 'user_id', 'order_id'),
    'media_files': ('id', 'business_id'),
    'order_items': ('id', 'order_id', 'product_id'),
    'order_transitions': ('id', 'order_id', 'actor_id'),
    'orders': ('id', 'business_id', 'student_id', 'cancelled_by', 'verified_by'),
    'products': ('id', 'business_id'),
    'refresh_sessions': ('id', 'user_id', 'family_id'),
    'reviews': ('id', 'order_id', 'user_id', 'business_id', 'career_id', 'group_id'),
    'users': ('id', 'business_id'),
    'verification_tokens': ('id', 'user_id'),
}
WIDEN = {
    'academic_records': {'email': (160, 254), 'display_name': (100, 160)},
    'access_requests': {'email': (160, 254), 'display_name': (100, 160)},
    'businesses': {'name': (100, 160), 'category': (60, 80), 'description': (600, 2000)},
    'users': {'email': (160, 254), 'display_name': (100, 160)},
    'verification_tokens': {'email': (160, 254)},
}
LEGACY_CHECKS = {
    'businesses': ('version >= 1', 'next_order_number >= 1'),
    'products': ('version >= 1', 'price >= 0.01 AND price <= 10000',
                 'stock IS NULL OR stock >= 0', 'stock IS NULL OR stock != 0 OR NOT is_available'),
    'orders': ('order_number >= 1 AND version >= 1 AND total >= 0',
               "status IN ('pending','accepted','preparing','ready','completed','cancelled')"),
    'order_items': ('quantity > 0 AND price >= 0', 'reserved_quantity >= 0 AND reserved_quantity <= quantity'),
}


def batch(table):
    # SQLite batch recreation otherwise drops unnamed CHECKs from revision 0001.
    constraints = [sa.CheckConstraint(sql) for sql in LEGACY_CHECKS.get(table, ())] if op.get_bind().dialect.name == 'sqlite' else []
    return op.batch_alter_table(table, table_args=constraints)


def upgrade():
    op.create_table('account_audit_events',
    sa.Column('id', sa.Text(), nullable=False),
    sa.Column('actor_id', sa.Text(), nullable=True),
    sa.Column('action', sa.String(length=80), nullable=False),
    sa.Column('target_type', sa.String(length=32), nullable=False),
    sa.Column('target_id', sa.Text(), nullable=False),
    sa.Column('data', sa.JSON(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['actor_id'], ['users.id'], ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_account_audit_events_actor_id'), 'account_audit_events', ['actor_id'], unique=False)
    op.create_index('ix_account_audit_target', 'account_audit_events', ['target_type', 'target_id'], unique=False)
    op.create_table('devices',
    sa.Column('id', sa.Text(), nullable=False),
    sa.Column('user_id', sa.Text(), nullable=False),
    sa.Column('token', sa.Text(), nullable=False),
    sa.Column('token_hash', sa.String(length=64), nullable=False),
    sa.Column('platform', sa.String(length=16), nullable=False),
    sa.Column('provider', sa.String(length=16), nullable=False),
    sa.Column('session_family_id', sa.Text(), nullable=False),
    sa.Column('last_active_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.CheckConstraint("platform IN ('android','ios','web')", name='ck_device_platform'),
    sa.CheckConstraint("provider = 'fcm' OR (provider = 'apns' AND platform = 'ios') OR (provider = 'webpush' AND platform = 'web')", name='ck_device_platform_provider'),
    sa.CheckConstraint("provider IN ('fcm','apns','webpush')", name='ck_device_provider'),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('token_hash')
    )
    op.create_index(op.f('ix_devices_session_family_id'), 'devices', ['session_family_id'], unique=False)
    op.create_index(op.f('ix_devices_user_id'), 'devices', ['user_id'], unique=False)
    op.create_table('product_reviews',
    sa.Column('id', sa.Text(), nullable=False),
    sa.Column('order_id', sa.Text(), nullable=False),
    sa.Column('product_id', sa.Text(), nullable=False),
    sa.Column('user_id', sa.Text(), nullable=False),
    sa.Column('rating', sa.Integer(), nullable=False),
    sa.Column('comment', sa.Text(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.CheckConstraint('rating BETWEEN 1 AND 5', name='ck_product_review_rating'),
    sa.ForeignKeyConstraint(['order_id'], ['orders.id'], ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['product_id'], ['products.id'], ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('order_id', 'product_id', name='uq_product_review_order_product')
    )
    op.create_index('ix_product_reviews_product_created', 'product_reviews', ['product_id', 'created_at', 'id'], unique=False)
    op.create_index('ix_product_reviews_user', 'product_reviews', ['user_id'], unique=False)
    op.create_table('push_deliveries',
    sa.Column('id', sa.Text(), nullable=False),
    sa.Column('outbox_event_id', sa.Integer(), nullable=False),
    sa.Column('event_id', sa.Text(), nullable=False),
    sa.Column('device_id', sa.Text(), nullable=True),
    sa.Column('user_id', sa.Text(), nullable=False),
    sa.Column('payload', sa.JSON(), nullable=False),
    sa.Column('state', sa.String(length=16), nullable=False),
    sa.Column('attempts', sa.Integer(), nullable=False),
    sa.Column('next_attempt_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('locked_until', sa.DateTime(timezone=True), nullable=True),
    sa.Column('lease_id', sa.Text(), nullable=True),
    sa.Column('last_error', sa.String(length=80), nullable=True),
    sa.Column('provider_message_id', sa.Text(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('sent_at', sa.DateTime(timezone=True), nullable=True),
    sa.CheckConstraint("state IN ('pending','sending','retry','unconfigured','sent','dead','cancelled')", name='ck_push_state'),
    sa.CheckConstraint('attempts >= 0', name='ck_push_attempts'),
    sa.ForeignKeyConstraint(['device_id'], ['devices.id'], ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['outbox_event_id'], ['outbox_events.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('outbox_event_id', 'device_id', name='uq_push_event_device')
    )
    op.create_index('ix_push_due', 'push_deliveries', ['state', 'next_attempt_at'], unique=False)

    # Public identifiers become TEXT without changing any actual ID value.
    for table, columns in ID_COLUMNS.items():
        with batch(table) as alter:
            for column in columns:
                old_length = 128 if column in {'career_id', 'group_id'} or table in {'careers', 'academic_groups'} else 36
                alter.alter_column(column, existing_type=sa.String(old_length), type_=sa.Text())
            for column, (previous, current) in WIDEN.get(table, {}).items():
                alter.alter_column(column, existing_type=sa.String(previous), type_=sa.String(current))

    with batch('businesses') as alter:
        alter.add_column(sa.Column('image_url', sa.String(2048), nullable=True))
    with batch('users') as alter:
        alter.add_column(sa.Column('numero_de_control', sa.String(100), nullable=True))
        alter.add_column(sa.Column('avatar_url', sa.String(1000), nullable=True))
        alter.add_column(sa.Column('institutional_verified_at', sa.DateTime(timezone=True), nullable=True))
        alter.add_column(sa.Column('last_login_at', sa.DateTime(timezone=True), nullable=True))
        alter.create_unique_constraint('uq_users_numero_de_control', ['numero_de_control'])
    # The authoritative current roster supplies the value. No historical
    # verification/login date is invented for migrated accounts.
    op.execute(sa.text("UPDATE users SET numero_de_control = (SELECT institutional_id FROM academic_records "
                       "WHERE academic_records.email = users.email AND kind = 'student') WHERE role = 'user'"))
    with batch('verification_tokens') as alter:
        alter.add_column(sa.Column('registration_data', sa.JSON(), nullable=True))
        alter.create_index('ix_verification_tokens_expiry', ['expires_at'])
    with batch('refresh_sessions') as alter:
        alter.add_column(sa.Column('device_id', sa.Text(), nullable=True))
        alter.add_column(sa.Column('replaced_by_id', sa.Text(), nullable=True))
        alter.create_foreign_key('fk_refresh_sessions_device_id', 'devices', ['device_id'], ['id'], ondelete='SET NULL')
        alter.create_foreign_key('fk_refresh_sessions_replaced_by_id', 'refresh_sessions', ['replaced_by_id'], ['id'], ondelete='SET NULL')
        alter.create_index('ix_refresh_sessions_expiry', ['expires_at'])
        alter.create_index('ix_refresh_sessions_user_revoked', ['user_id', 'revoked_at'])
    with batch('media_files') as alter:
        alter.alter_column('business_id', existing_type=sa.Text(), nullable=True)
        alter.add_column(sa.Column('owner_id', sa.Text(), nullable=True))
        alter.add_column(sa.Column('purpose', sa.String(16), nullable=True))
        alter.add_column(sa.Column('width', sa.Integer(), nullable=True))
        alter.add_column(sa.Column('height', sa.Integer(), nullable=True))
        alter.add_column(sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True))
        alter.create_foreign_key('fk_media_files_owner_id', 'users', ['owner_id'], ['id'], ondelete='RESTRICT')
        alter.create_index('ix_media_files_owner_id', ['owner_id'])
    # Old uploads were exclusively product images. Original uploader is unknown;
    # keep owner_id NULL and preserve access via the existing business relation.
    op.execute(sa.text("UPDATE media_files SET purpose = 'product'"))
    with batch('media_files') as alter:
        alter.alter_column('purpose', existing_type=sa.String(16), nullable=False)
    with batch('products') as alter:
        alter.add_column(sa.Column('subcategory', sa.String(80), nullable=True))
        alter.add_column(sa.Column('preparation_minutes', sa.Integer(), nullable=True))
        alter.add_column(sa.Column('calories', sa.Integer(), nullable=True))
        alter.add_column(sa.Column('manual_available', sa.Boolean(), nullable=True))
        alter.add_column(sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True))
        alter.create_index('ix_products_business_available', ['business_id', 'is_available'])
        alter.create_check_constraint('ck_product_preparation_minutes', 'preparation_minutes IS NULL OR preparation_minutes >= 0')
        alter.create_check_constraint('ck_product_calories', 'calories IS NULL OR calories >= 0')
    op.execute(sa.text('UPDATE products SET manual_available = is_available'))
    with batch('products') as alter:
        alter.alter_column('manual_available', existing_type=sa.Boolean(), nullable=False)
    with batch('orders') as alter:
        alter.add_column(sa.Column('customer_institutional_id', sa.String(100), nullable=True))
        alter.add_column(sa.Column('subtotal', sa.Numeric(14, 2), nullable=True))
        alter.add_column(sa.Column('cancelled_by_role', sa.String(16), nullable=True))
        alter.add_column(sa.Column('verified_at', sa.DateTime(timezone=True), nullable=True))
        alter.create_index('ix_orders_business_updated', ['business_id', 'status', 'updated_at', 'id'])
        alter.create_index('ix_orders_student_status', ['student_id', 'status'])
        # Previous eight-digit codes are neither truncated nor made globally
        # unique retroactively. New six-character codes have a DB uniqueness gate.
        alter.create_index('uq_orders_v3_pickup_code', ['pickup_code'], unique=True,
                           sqlite_where=sa.text('length(pickup_code) = 6'),
                           postgresql_where=sa.text('length(pickup_code) = 6'))
    op.execute(sa.text('UPDATE orders SET subtotal = total'))
    op.execute(sa.text('UPDATE orders SET verified_at = completed_at WHERE verification_method IS NOT NULL'))
    op.execute(sa.text("UPDATE orders SET cancelled_by_role = CASE WHEN cancelled_by = student_id "
                       "THEN 'ALUMNO' ELSE 'COCINA' END WHERE cancelled_by IS NOT NULL"))
    # Customer academic identifiers, previous actor roles and exact deleted_at
    # cannot be reconstructed honestly from the old schema: remain NULL.
    with batch('order_transitions') as alter:
        alter.add_column(sa.Column('action', sa.String(48), nullable=True))
        alter.add_column(sa.Column('actor_role', sa.String(16), nullable=True))
        alter.add_column(sa.Column('payload', sa.JSON(), nullable=True))
    with batch('idempotency_records') as alter:
        alter.add_column(sa.Column('expires_at', sa.DateTime(timezone=True), nullable=True))
        alter.add_column(sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True))
    op.execute(sa.text('UPDATE idempotency_records SET updated_at = created_at'))
    with batch('idempotency_records') as alter:
        alter.alter_column('updated_at', existing_type=sa.DateTime(timezone=True), nullable=False)
    with batch('reviews') as alter:
        alter.add_column(sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True))
    op.execute(sa.text('UPDATE reviews SET updated_at = created_at'))
    with batch('reviews') as alter:
        alter.alter_column('updated_at', existing_type=sa.DateTime(timezone=True), nullable=False)
    with batch('outbox_events') as alter:
        alter.alter_column('topic', existing_type=sa.String(200), type_=sa.Text())
        alter.add_column(sa.Column('publish_attempts', sa.Integer(), nullable=True))
        alter.add_column(sa.Column('last_error', sa.String(80), nullable=True))
        alter.add_column(sa.Column('next_attempt_at', sa.DateTime(timezone=True), nullable=True))
        alter.create_index('ix_outbox_events_next_attempt_at', ['next_attempt_at'])
    op.execute(sa.text('UPDATE outbox_events SET publish_attempts = 0'))
    with batch('outbox_events') as alter:
        alter.alter_column('publish_attempts', existing_type=sa.Integer(), nullable=False)
    if op.get_bind().dialect.name == 'sqlite':
        if op.get_bind().exec_driver_sql('PRAGMA foreign_key_check').fetchall():
            raise RuntimeError('V3 migration detected invalid historical foreign keys; restore the verified backup.')


def downgrade():
    # Shrinking TEXT IDs or removing V3 audit/review/device data is not a safe
    # inverse. A controlled rollback restores the pre-upgrade DB + media backup.
    raise RuntimeError('V3 rollback requires the verified pre-upgrade database and media backup; automatic data loss is disabled.')
