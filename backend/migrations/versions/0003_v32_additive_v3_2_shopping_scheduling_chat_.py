"""Additive V3.2 shopping scheduling chat vouchers

Revision ID: 0003_v32
Revises: 0002_v3
"""
from alembic import op
import sqlalchemy as sa


revision = '0003_v32'
down_revision = '0002_v3'
branch_labels = None
depends_on = None


def upgrade():
    # Frozen additive schema. No existing table, column or value is removed.
    op.create_table('chat_closures',
    sa.Column('id', sa.Text(), nullable=False),
    sa.Column('student_proof', sa.String(length=64), nullable=False),
    sa.Column('business_proof', sa.String(length=64), nullable=False),
    sa.Column('closed_at', sa.DateTime(timezone=True), nullable=False),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_table('cart_items',
    sa.Column('id', sa.Text(), nullable=False),
    sa.Column('user_id', sa.Text(), nullable=False),
    sa.Column('product_id', sa.Text(), nullable=False),
    sa.Column('quantity', sa.Integer(), nullable=False),
    sa.Column('notes', sa.String(length=500), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.CheckConstraint('quantity BETWEEN 1 AND 99', name='ck_cart_quantity'),
    sa.ForeignKeyConstraint(['product_id'], ['products.id'], ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('user_id', 'product_id', name='uq_cart_user_product')
    )
    op.create_index(op.f('ix_cart_items_user_id'), 'cart_items', ['user_id'], unique=False)
    op.create_table('favorites',
    sa.Column('id', sa.Text(), nullable=False),
    sa.Column('user_id', sa.Text(), nullable=False),
    sa.Column('product_id', sa.Text(), nullable=False),
    sa.Column('notes', sa.String(length=500), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['product_id'], ['products.id'], ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('user_id', 'product_id', name='uq_favorite_user_product')
    )
    op.create_index(op.f('ix_favorites_user_id'), 'favorites', ['user_id'], unique=False)
    op.create_table('chats',
    sa.Column('id', sa.Text(), nullable=False),
    sa.Column('student_id', sa.Text(), nullable=False),
    sa.Column('business_id', sa.Text(), nullable=False),
    sa.Column('order_id', sa.Text(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('last_activity_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['order_id'], ['orders.id'], ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['student_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('student_id', 'business_id', name='uq_chat_participants')
    )
    op.create_index(op.f('ix_chats_business_id'), 'chats', ['business_id'], unique=False)
    op.create_index(op.f('ix_chats_last_activity_at'), 'chats', ['last_activity_at'], unique=False)
    op.create_index(op.f('ix_chats_student_id'), 'chats', ['student_id'], unique=False)
    op.create_table('meal_voucher_uses',
    sa.Column('id', sa.Text(), nullable=False),
    sa.Column('user_id', sa.Text(), nullable=False),
    sa.Column('order_id', sa.Text(), nullable=False),
    sa.Column('local_date', sa.Date(), nullable=False),
    sa.Column('state', sa.String(length=16), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.CheckConstraint("state IN ('reserved','consumed','released')", name='ck_meal_voucher_state'),
    sa.ForeignKeyConstraint(['order_id'], ['orders.id'], ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('order_id')
    )
    op.create_index('uq_meal_voucher_active_day', 'meal_voucher_uses', ['user_id', 'local_date'], unique=True, postgresql_where=sa.text("state IN ('reserved','consumed')"), sqlite_where=sa.text("state IN ('reserved','consumed')"))
    op.create_table('chat_messages',
    sa.Column('id', sa.Text(), nullable=False),
    sa.Column('chat_id', sa.Text(), nullable=False),
    sa.Column('sender_id', sa.Text(), nullable=False),
    sa.Column('sender_role', sa.String(length=16), nullable=False),
    sa.Column('text', sa.String(length=1000), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.CheckConstraint('length(text) BETWEEN 1 AND 1000', name='ck_chat_text'),
    sa.ForeignKeyConstraint(['chat_id'], ['chats.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['sender_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_chat_messages_created', 'chat_messages', ['chat_id', 'created_at', 'id'], unique=False)
    op.add_column('businesses', sa.Column('cover_image_url', sa.String(length=2048), nullable=True))
    op.add_column('businesses', sa.Column('pickup_timeout_minutes', sa.Integer(), nullable=False, server_default='30'))
    op.add_column('businesses', sa.Column('auto_close_enabled', sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column('businesses', sa.Column('close_time_local', sa.String(length=5), nullable=True))
    op.add_column('businesses', sa.Column('postponed_close_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('businesses', sa.Column('last_auto_close_date', sa.Date(), nullable=True))
    op.add_column('orders', sa.Column('pickup_soon_notified_at', sa.DateTime(timezone=True), nullable=True))
    predicate = sa.text("scheduled_pickup_time IS NOT NULL AND pickup_soon_notified_at IS NULL AND status IN ('pending','accepted','preparing','ready')")
    op.create_index('ix_orders_scheduled_alert_due', 'orders', ['scheduled_pickup_time'],
                    postgresql_where=predicate, sqlite_where=predicate)

    # Drop temporary backfill defaults only after old rows have their values.
    # SQLite recreation must explicitly preserve unnamed checks from 0001.
    checks = [sa.CheckConstraint('version >= 1'), sa.CheckConstraint('next_order_number >= 1')] if op.get_bind().dialect.name == 'sqlite' else []
    with op.batch_alter_table('businesses', table_args=checks) as alter:
        alter.alter_column('pickup_timeout_minutes', existing_type=sa.Integer(), server_default=None)
        alter.alter_column('auto_close_enabled', existing_type=sa.Boolean(), server_default=None)
        alter.create_check_constraint('ck_business_pickup_timeout', 'pickup_timeout_minutes BETWEEN 5 AND 180')
        alter.create_check_constraint('ck_business_close_time', 'NOT auto_close_enabled OR close_time_local IS NOT NULL')
    for table, columns in [('reviews', ('rating', 'food_rating', 'service_rating')), ('product_reviews', ('rating',))]:
        with op.batch_alter_table(table) as alter:
            for column in columns:
                name = 'ck_product_review_rating' if table == 'product_reviews' else 'ck_review_' + column
                alter.drop_constraint(name, type_='check')
                expression = column + ' BETWEEN 0 AND 5'
                if table == 'reviews':
                    expression = column + ' IS NULL OR ' + expression
                alter.create_check_constraint(name, expression)


def downgrade():
    raise RuntimeError('Restore a verified pre-upgrade backup; automatic downgrade would erase V3.2 data.')
