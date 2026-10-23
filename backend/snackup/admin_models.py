"""Administrative data. Reviews retain academic snapshots, never client claims."""

from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base, new_id, utcnow


class Review(Base):
    __tablename__ = "reviews"
    __table_args__ = (
        UniqueConstraint("order_id", name="uq_review_order"),
        CheckConstraint("rating IS NULL OR rating BETWEEN 1 AND 5", name="ck_review_rating"),
        CheckConstraint("food_rating IS NULL OR food_rating BETWEEN 1 AND 5", name="ck_review_food_rating"),
        CheckConstraint("service_rating IS NULL OR service_rating BETWEEN 1 AND 5", name="ck_review_service_rating"),
        Index("ix_reviews_business_created", "business_id", "created_at", "id"),
    )
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    order_id: Mapped[str] = mapped_column(ForeignKey("orders.id"), nullable=False)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False)
    business_id: Mapped[str] = mapped_column(ForeignKey("businesses.id"), nullable=False)
    rating: Mapped[int | None] = mapped_column(Integer)
    food_rating: Mapped[int | None] = mapped_column(Integer)
    service_rating: Mapped[int | None] = mapped_column(Integer)
    career_id: Mapped[str | None] = mapped_column(ForeignKey("careers.id"))
    group_id: Mapped[str | None] = mapped_column(ForeignKey("academic_groups.id"))
    career_name: Mapped[str] = mapped_column(String(200), default="", nullable=False)
    group_name: Mapped[str] = mapped_column(String(200), default="", nullable=False)
    comment: Mapped[str] = mapped_column(Text, default="", nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)


class Followup(Base):
    __tablename__ = "followups"
    __table_args__ = (
        CheckConstraint("version >= 1", name="ck_followup_version"),
        CheckConstraint("status IN ('pending', 'in_review', 'resolved')", name="ck_followup_status"),
        Index("ix_followups_updated", "updated_at", "review_id"),
    )
    review_id: Mapped[str] = mapped_column(ForeignKey("reviews.id"), primary_key=True)
    business_id: Mapped[str] = mapped_column(ForeignKey("businesses.id"), nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False)
    assignee: Mapped[str] = mapped_column(String(120), nullable=False)
    note: Mapped[str] = mapped_column(Text, nullable=False)
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)


class FollowupEvent(Base):
    __tablename__ = "followup_events"
    __table_args__ = (
        UniqueConstraint("review_id", "version", name="uq_followup_event_version"),
        CheckConstraint("version >= 1", name="ck_followup_event_version"),
        CheckConstraint("status IN ('pending', 'in_review', 'resolved')", name="ck_followup_event_status"),
        Index("ix_followup_events_review_version", "review_id", "version"),
    )
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    review_id: Mapped[str] = mapped_column(ForeignKey("followups.review_id"), nullable=False)
    business_id: Mapped[str] = mapped_column(ForeignKey("businesses.id"), nullable=False)
    actor_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False)
    assignee: Mapped[str] = mapped_column(String(120), nullable=False)
    note: Mapped[str] = mapped_column(Text, nullable=False)
    version: Mapped[int] = mapped_column(Integer, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)


class AccessDecision(Base):
    __tablename__ = "access_decisions"
    __table_args__ = (UniqueConstraint("request_id", name="uq_access_decision_request"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    request_id: Mapped[str] = mapped_column(ForeignKey("access_requests.id"), nullable=False)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False)
    actor_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False)
    decision: Mapped[str] = mapped_column(String(20), nullable=False)
    role: Mapped[str] = mapped_column(String(20), nullable=False)
    business_id: Mapped[str | None] = mapped_column(ForeignKey("businesses.id"))
    note: Mapped[str] = mapped_column(String(500), nullable=False, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)
