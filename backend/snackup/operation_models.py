"""Relational catalog and immutable order snapshots; no demonstration fixtures."""
from datetime import date, datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import Boolean, CheckConstraint, Date, DateTime, ForeignKey, Index, Integer, JSON, Numeric, String, Text, UniqueConstraint, text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .db import Base, new_id, utcnow


class Business(Base):
    __tablename__ = "businesses"
    __table_args__ = (CheckConstraint("version >= 1"), CheckConstraint("next_order_number >= 1"),
                      CheckConstraint('pickup_timeout_minutes BETWEEN 5 AND 180', name='ck_business_pickup_timeout'),
                      CheckConstraint('NOT auto_close_enabled OR close_time_local IS NOT NULL', name='ck_business_close_time'))
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    name: Mapped[str] = mapped_column(String(160))
    category: Mapped[str] = mapped_column(String(80), default="")
    description: Mapped[str] = mapped_column(String(2000), default="")
    image_url: Mapped[str | None] = mapped_column(String(2048), nullable=True)
    cover_image_url: Mapped[str | None] = mapped_column(String(2048), nullable=True)
    pickup_timeout_minutes: Mapped[int] = mapped_column(Integer, default=30)
    auto_close_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    close_time_local: Mapped[str | None] = mapped_column(String(5), nullable=True)
    postponed_close_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_auto_close_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    timezone: Mapped[str] = mapped_column(String(80), default="America/Mexico_City")
    cafeteria_id: Mapped[str] = mapped_column(String(120))
    cafeteria_name: Mapped[str] = mapped_column(String(160))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    is_open: Mapped[bool] = mapped_column(Boolean, default=False)
    version: Mapped[int] = mapped_column(Integer, default=1)
    next_order_number: Mapped[int] = mapped_column(Integer, default=1)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Product(Base):
    __tablename__ = "products"
    __table_args__ = (
        CheckConstraint("version >= 1"), CheckConstraint("price >= 0.01 AND price <= 10000"),
        CheckConstraint("stock IS NULL OR stock >= 0"),
        CheckConstraint("stock IS NULL OR stock != 0 OR NOT is_available"),
        CheckConstraint("preparation_minutes IS NULL OR preparation_minutes >= 0", name="ck_product_preparation_minutes"),
        CheckConstraint("calories IS NULL OR calories >= 0", name="ck_product_calories"),
        Index("ix_products_business_catalog", "business_id", "is_deleted", "category"),
        Index("ix_products_business_available", "business_id", "is_available"),
    )
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    business_id: Mapped[str] = mapped_column(ForeignKey("businesses.id", ondelete="RESTRICT"))
    name: Mapped[str] = mapped_column(String(160))
    description: Mapped[str] = mapped_column(String(2000), default="")
    category: Mapped[str] = mapped_column(String(120))
    subcategory: Mapped[str | None] = mapped_column(String(80), nullable=True)
    preparation_minutes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    calories: Mapped[int | None] = mapped_column(Integer, nullable=True)
    price: Mapped[Decimal] = mapped_column(Numeric(12, 2))
    stock: Mapped[int | None] = mapped_column(Integer, nullable=True)
    image_url: Mapped[str | None] = mapped_column(String(2048), nullable=True)
    is_available: Mapped[bool] = mapped_column(Boolean, default=True)
    # Operator intent is independent from the effective stock-derived state.
    manual_available: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    is_featured: Mapped[bool] = mapped_column(Boolean, default=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    version: Mapped[int] = mapped_column(Integer, default=1)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Order(Base):
    __tablename__ = "orders"
    __table_args__ = (
        UniqueConstraint("business_id", "order_number", name="uq_business_order_number"),
        CheckConstraint("order_number >= 1 AND version >= 1 AND total >= 0"),
        CheckConstraint("status IN ('pending','accepted','preparing','ready','completed','cancelled')"),
        Index("ix_orders_business_active", "business_id", "status", "created_at", "id"),
        Index("ix_orders_business_completed", "business_id", "completed_at"),
        Index("ix_orders_business_cancelled", "business_id", "cancelled_at"),
        Index("ix_orders_student_created", "student_id", "created_at", "id"),
        Index("ix_orders_business_updated", "business_id", "status", "updated_at", "id"),
        Index("ix_orders_student_status", "student_id", "status"),
        Index('ix_orders_scheduled_alert_due', 'scheduled_pickup_time',
              postgresql_where=text("scheduled_pickup_time IS NOT NULL AND pickup_soon_notified_at IS NULL AND status IN ('pending','accepted','preparing','ready')"),
              sqlite_where=text("scheduled_pickup_time IS NOT NULL AND pickup_soon_notified_at IS NULL AND status IN ('pending','accepted','preparing','ready')")),
        # Existing eight-digit codes remain valid and are never rewritten.
        Index("uq_orders_v3_pickup_code", "pickup_code", unique=True,
              sqlite_where=text("length(pickup_code) = 6"),
              postgresql_where=text("length(pickup_code) = 6")),
    )
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    business_id: Mapped[str] = mapped_column(ForeignKey("businesses.id", ondelete="RESTRICT"))
    student_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"))
    order_number: Mapped[int] = mapped_column(Integer)
    version: Mapped[int] = mapped_column(Integer, default=1)
    status: Mapped[str] = mapped_column(String(20), default="pending")
    customer_name: Mapped[str] = mapped_column(String(160))
    customer_institutional_id: Mapped[str | None] = mapped_column(String(100), nullable=True)
    payment_method: Mapped[str] = mapped_column(String(30), default="cash")
    payment_status: Mapped[str] = mapped_column(String(30), default="pay_at_pickup")
    total: Mapped[Decimal] = mapped_column(Numeric(14, 2))
    subtotal: Mapped[Decimal | None] = mapped_column(Numeric(14, 2), nullable=True)
    pickup_code: Mapped[str] = mapped_column(String(32))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    scheduled_pickup_time: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    pickup_soon_notified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    preparing_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    ready_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    cancel_reason: Mapped[str | None] = mapped_column(String(60), nullable=True)
    cancel_notes: Mapped[str | None] = mapped_column(String(500), nullable=True)
    cancelled_by: Mapped[str | None] = mapped_column(Text, nullable=True)
    cancelled_by_role: Mapped[str | None] = mapped_column(String(16), nullable=True)
    stock_restored: Mapped[bool] = mapped_column(Boolean, default=False)
    verification_method: Mapped[str | None] = mapped_column(String(10), nullable=True)
    verified_by: Mapped[str | None] = mapped_column(Text, nullable=True)
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    items: Mapped[list["OrderItem"]] = relationship(lazy="selectin", order_by="OrderItem.id")


class OrderItem(Base):
    __tablename__ = "order_items"
    __table_args__ = (
        CheckConstraint("quantity > 0 AND price >= 0"),
        CheckConstraint("reserved_quantity >= 0 AND reserved_quantity <= quantity"),
    )
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    order_id: Mapped[str] = mapped_column(ForeignKey("orders.id", ondelete="RESTRICT"), index=True)
    product_id: Mapped[str] = mapped_column(ForeignKey("products.id", ondelete="RESTRICT"), index=True)
    name: Mapped[str] = mapped_column(String(160))
    quantity: Mapped[int] = mapped_column(Integer)
    price: Mapped[Decimal] = mapped_column(Numeric(12, 2))
    notes: Mapped[str] = mapped_column(String(500), default="")
    reserved_quantity: Mapped[int] = mapped_column(Integer, default=0)


class MediaFile(Base):
    __tablename__ = "media_files"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    business_id: Mapped[str | None] = mapped_column(ForeignKey("businesses.id", ondelete="RESTRICT"), index=True, nullable=True)
    owner_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True, nullable=True)
    purpose: Mapped[str] = mapped_column(String(16), default="product", nullable=False)
    filename: Mapped[str] = mapped_column(String(80), unique=True)
    mime_type: Mapped[str] = mapped_column(String(30))
    size: Mapped[int] = mapped_column(Integer)
    width: Mapped[int | None] = mapped_column(Integer, nullable=True)
    height: Mapped[int | None] = mapped_column(Integer, nullable=True)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class OrderTransition(Base):
    __tablename__ = "order_transitions"
    __table_args__ = (UniqueConstraint("order_id", "version", name="uq_order_transition_version"),)
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    order_id: Mapped[str] = mapped_column(ForeignKey("orders.id", ondelete="RESTRICT"), index=True)
    actor_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"))
    from_status: Mapped[str | None] = mapped_column(String(20), nullable=True)
    to_status: Mapped[str] = mapped_column(String(20))
    version: Mapped[int] = mapped_column(Integer)
    action: Mapped[str | None] = mapped_column(String(48), nullable=True)
    actor_role: Mapped[str | None] = mapped_column(String(16), nullable=True)
    payload: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class IdempotencyRecord(Base):
    __tablename__ = "idempotency_records"
    __table_args__ = (UniqueConstraint("user_id", "key", name="uq_user_order_idempotency"),)
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"))
    key: Mapped[str] = mapped_column(String(128))
    payload_hash: Mapped[str] = mapped_column(String(64))
    order_id: Mapped[str] = mapped_column(ForeignKey("orders.id", ondelete="RESTRICT"))
    response_json: Mapped[dict[str, Any]] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
