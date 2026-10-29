"""Device registrations and durable, independently retried push deliveries.

Raw provider tokens are private credentials. They are never copied into the
outbox, API responses, audit records or delivery errors. A fixed-size digest
enforces token uniqueness without PostgreSQL's B-tree size limit on Web Push
subscriptions, which can contain a long endpoint and encryption keys.
"""
from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, Integer, JSON, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base, new_id, utcnow


class Device(Base):
    __tablename__ = "devices"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    token: Mapped[str] = mapped_column(Text, nullable=False)
    token_hash: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    platform: Mapped[str] = mapped_column(String(16), nullable=False)
    provider: Mapped[str] = mapped_column(String(16), nullable=False)
    session_family_id: Mapped[str] = mapped_column(Text, nullable=False, index=True)
    last_active_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow, onupdate=utcnow)
    __table_args__ = (
        CheckConstraint("platform IN ('android','ios','web')", name="ck_device_platform"),
        CheckConstraint("provider IN ('fcm','apns','webpush')", name="ck_device_provider"),
        CheckConstraint("provider = 'fcm' OR (provider = 'apns' AND platform = 'ios') OR "
                        "(provider = 'webpush' AND platform = 'web')", name="ck_device_platform_provider"),
    )


class PushDelivery(Base):
    __tablename__ = "push_deliveries"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    outbox_event_id: Mapped[int] = mapped_column(ForeignKey("outbox_events.id", ondelete="CASCADE"), nullable=False)
    event_id: Mapped[str] = mapped_column(Text, nullable=False)
    device_id: Mapped[str | None] = mapped_column(ForeignKey("devices.id", ondelete="SET NULL"), nullable=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    payload: Mapped[dict] = mapped_column(JSON, nullable=False)
    state: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    next_attempt_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)
    locked_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    lease_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    last_error: Mapped[str | None] = mapped_column(String(80), nullable=True)
    provider_message_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow, onupdate=utcnow)
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    __table_args__ = (
        UniqueConstraint("outbox_event_id", "device_id", name="uq_push_event_device"),
        CheckConstraint("state IN ('pending','sending','retry','unconfigured','sent','dead','cancelled')", name="ck_push_state"),
        CheckConstraint("attempts >= 0", name="ck_push_attempts"),
        Index("ix_push_due", "state", "next_attempt_at"),
    )
