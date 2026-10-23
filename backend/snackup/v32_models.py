"""Additive V3.2 storage. Existing orders, identities and opinions keep their IDs."""
from datetime import date, datetime

from sqlalchemy import CheckConstraint, Date, DateTime, ForeignKey, Index, Integer, String, Text, UniqueConstraint, text
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base, new_id, utcnow


class CartItem(Base):
    __tablename__ = 'cart_items'
    __table_args__ = (UniqueConstraint('user_id', 'product_id', name='uq_cart_user_product'),
                      CheckConstraint('quantity BETWEEN 1 AND 99', name='ck_cart_quantity'))
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    product_id: Mapped[str] = mapped_column(ForeignKey('products.id', ondelete='RESTRICT'))
    quantity: Mapped[int] = mapped_column(Integer)
    notes: Mapped[str] = mapped_column(String(500), default='')
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Favorite(Base):
    __tablename__ = 'favorites'
    __table_args__ = (UniqueConstraint('user_id', 'product_id', name='uq_favorite_user_product'),)
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    product_id: Mapped[str] = mapped_column(ForeignKey('products.id', ondelete='RESTRICT'))
    notes: Mapped[str] = mapped_column(String(500), default='')
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class MealVoucherUse(Base):
    __tablename__ = 'meal_voucher_uses'
    __table_args__ = (
        CheckConstraint("state IN ('reserved','consumed','released')", name='ck_meal_voucher_state'),
        Index('uq_meal_voucher_active_day', 'user_id', 'local_date', unique=True,
              postgresql_where=text("state IN ('reserved','consumed')"),
              sqlite_where=text("state IN ('reserved','consumed')")),
    )
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id', ondelete='RESTRICT'))
    order_id: Mapped[str] = mapped_column(ForeignKey('orders.id', ondelete='RESTRICT'), unique=True)
    local_date: Mapped[date] = mapped_column(Date)
    state: Mapped[str] = mapped_column(String(16), default='reserved')
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Chat(Base):
    __tablename__ = 'chats'
    __table_args__ = (UniqueConstraint('student_id', 'business_id', name='uq_chat_participants'),)
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    student_id: Mapped[str] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    business_id: Mapped[str] = mapped_column(ForeignKey('businesses.id', ondelete='CASCADE'), index=True)
    order_id: Mapped[str | None] = mapped_column(ForeignKey('orders.id', ondelete='SET NULL'), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    last_activity_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)


class ChatMessage(Base):
    __tablename__ = 'chat_messages'
    __table_args__ = (Index('ix_chat_messages_created', 'chat_id', 'created_at', 'id'),
                      CheckConstraint('length(text) BETWEEN 1 AND 1000', name='ck_chat_text'))
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    chat_id: Mapped[str] = mapped_column(ForeignKey('chats.id', ondelete='CASCADE'))
    sender_id: Mapped[str] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'))
    sender_role: Mapped[str] = mapped_column(String(16))
    text: Mapped[str] = mapped_column(String(1000))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class ChatClosure(Base):
    """Authorization receipt only: no messages, order, participant IDs or history."""
    __tablename__ = 'chat_closures'
    id: Mapped[str] = mapped_column(Text, primary_key=True)
    student_proof: Mapped[str] = mapped_column(String(64))
    business_proof: Mapped[str] = mapped_column(String(64))
    closed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
