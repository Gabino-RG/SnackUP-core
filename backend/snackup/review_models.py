"""Product reviews complement the existing, academically attributed business rating.

Business ratings deliberately remain in ``reviews``: its historical rows and
administrative follow-ups are the same opinions exposed by the V3 rating route.
"""
from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, Integer, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base, new_id, utcnow


class ProductReview(Base):
    __tablename__ = 'product_reviews'
    __table_args__ = (
        UniqueConstraint('order_id', 'product_id', name='uq_product_review_order_product'),
        CheckConstraint('rating BETWEEN 1 AND 5', name='ck_product_review_rating'),
        Index('ix_product_reviews_product_created', 'product_id', 'created_at', 'id'),
        Index('ix_product_reviews_user', 'user_id'),
    )
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    order_id: Mapped[str] = mapped_column(ForeignKey('orders.id', ondelete='RESTRICT'))
    product_id: Mapped[str] = mapped_column(ForeignKey('products.id', ondelete='RESTRICT'))
    user_id: Mapped[str] = mapped_column(ForeignKey('users.id', ondelete='RESTRICT'))
    rating: Mapped[int] = mapped_column(Integer)
    comment: Mapped[str] = mapped_column(Text, default='')
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)
