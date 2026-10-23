"""Identity records. Institutional roster data never grants a SnackUP staff role."""
from datetime import datetime

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, Index, Integer, JSON, String, Text, UniqueConstraint, text
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base, new_id, utcnow


class User(Base):
    __tablename__ = "users"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    email: Mapped[str] = mapped_column(String(254), unique=True, nullable=False)
    display_name: Mapped[str] = mapped_column(String(160), nullable=False)
    password_hash: Mapped[str] = mapped_column(String(256), nullable=False)
    role: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
    business_id: Mapped[str | None] = mapped_column(ForeignKey("businesses.id"), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    is_master: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    approval_status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
    email_verified: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    auth_version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    numero_de_control: Mapped[str | None] = mapped_column(String(100), unique=True, nullable=True)
    avatar_url: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    institutional_verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)
    __table_args__ = (
        CheckConstraint("role IN ('admin','business','user','pending')", name="ck_user_role"),
        CheckConstraint("approval_status IN ('approved','pending','rejected')", name="ck_user_approval"),
        CheckConstraint("NOT is_master OR role = 'admin'", name="ck_master_role"),
        CheckConstraint("role = 'business' OR business_id IS NULL", name="ck_user_business_role"),
        Index("uq_active_business_operator", "business_id", unique=True,
              sqlite_where=text("role = 'business' AND is_active = 1 AND approval_status = 'approved'"),
              postgresql_where=text("role = 'business' AND is_active = true AND approval_status = 'approved'")),
    )


class Career(Base):
    __tablename__ = "careers"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)


class AcademicGroup(Base):
    __tablename__ = "academic_groups"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    career_id: Mapped[str] = mapped_column(ForeignKey("careers.id"), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)


class AcademicRecord(Base):
    __tablename__ = "academic_records"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    email: Mapped[str] = mapped_column(String(254), nullable=False, unique=True)
    institutional_id: Mapped[str] = mapped_column(String(100), nullable=False)
    display_name: Mapped[str] = mapped_column(String(160), nullable=False)
    kind: Mapped[str] = mapped_column(String(16), nullable=False)
    career_id: Mapped[str | None] = mapped_column(ForeignKey("careers.id"), nullable=True)
    group_id: Mapped[str | None] = mapped_column(ForeignKey("academic_groups.id"), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    source: Mapped[str] = mapped_column(String(200), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)
    __table_args__ = (
        UniqueConstraint("kind", "institutional_id", name="uq_roster_identity"),
        CheckConstraint("kind IN ('student','staff')", name="ck_roster_kind"),
        CheckConstraint("kind != 'student' OR career_id IS NOT NULL", name="ck_student_career"),
        CheckConstraint("group_id IS NULL OR career_id IS NOT NULL", name="ck_roster_group_career"),
    )


class RefreshSession(Base):
    __tablename__ = "refresh_sessions"
    __table_args__ = (Index("ix_refresh_sessions_user_revoked", "user_id", "revoked_at"),
                      Index("ix_refresh_sessions_expiry", "expires_at"))
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    family_id: Mapped[str] = mapped_column(Text, nullable=False, index=True)
    token_hash: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    auth_version: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    rotated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    device_id: Mapped[str | None] = mapped_column(ForeignKey("devices.id", ondelete="SET NULL"), nullable=True)
    replaced_by_id: Mapped[str | None] = mapped_column(ForeignKey("refresh_sessions.id", ondelete="SET NULL"), nullable=True)


class AccessRequest(Base):
    __tablename__ = "access_requests"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, unique=True)
    email: Mapped[str] = mapped_column(String(254), nullable=False)
    display_name: Mapped[str] = mapped_column(String(160), nullable=False)
    requested_role: Mapped[str] = mapped_column(String(16), nullable=False)
    request_context: Mapped[str] = mapped_column(String(400), nullable=False, default="")
    provider: Mapped[str] = mapped_column(String(16), nullable=False, default="password")
    email_verified: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    approval_status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending", index=True)
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
    reviewed_by: Mapped[str | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    note: Mapped[str] = mapped_column(String(500), nullable=False, default="")
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    __table_args__ = (
        CheckConstraint("requested_role IN ('admin','business')", name="ck_requested_role"),
        CheckConstraint("approval_status IN ('pending','approved','rejected')", name="ck_request_approval"),
    )


class VerificationToken(Base):
    __tablename__ = "verification_tokens"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    email: Mapped[str] = mapped_column(String(254), nullable=False)
    purpose: Mapped[str] = mapped_column(String(16), nullable=False)
    token_hash: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    # A pending V3 registration is applied only after proof of email ownership.
    # May contain a password hash, never a plaintext password; never serialized.
    registration_data: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
    __table_args__ = (CheckConstraint("purpose IN ('verify','reset')", name="ck_verification_purpose"),
                      Index("ix_verification_tokens_expiry", "expires_at"))


class AccountAuditEvent(Base):
    __tablename__ = "account_audit_events"
    id: Mapped[str] = mapped_column(Text, primary_key=True, default=new_id)
    actor_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    action: Mapped[str] = mapped_column(String(80), nullable=False)
    target_type: Mapped[str] = mapped_column(String(32), nullable=False)
    target_id: Mapped[str] = mapped_column(Text, nullable=False)
    data: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
    __table_args__ = (Index("ix_account_audit_target", "target_type", "target_id"),)


def audit_event(db, actor_id, action, target_type, target_id, data=None):
    """Append nonsensitive metadata in the caller's mutation transaction."""
    db.add(AccountAuditEvent(actor_id=actor_id, action=action, target_type=target_type,
                             target_id=target_id, data=data or {}))
