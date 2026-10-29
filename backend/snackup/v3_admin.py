"""V3 business/account lifecycle with atomic kitchen provisioning and audit."""
from typing import Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, Body, Depends, Query, Request, Response
from pydantic import BaseModel, Field
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from .admin import _lock_admins
from .auth import current_user, hash_password, require_admin, revoke_user_sessions
from .common import page_result, require, version_check
from .db import emit_event, get_db, new_id, utcnow
from .errors import ApiError
from .identity import _mail_token, normalize_email
from .identity_models import AcademicRecord, RefreshSession, User, audit_event
from .mailer import mail_available
from .operation_models import Business, Order
from .v3_identity import AppUserResponse, InputModel, serialize_v3_user

router = APIRouter(tags=["V3 · Administración"])


class PaginationResponse(BaseModel):
    page: int
    limit: int
    total: int
    totalPages: int


class BusinessResponse(BaseModel):
    id: str
    ownerId: str | None
    name: str
    category: str
    description: str
    imageUrl: str | None
    isOpen: bool
    isActive: bool
    timezone: str
    averageRating: float
    totalRatings: int
    totalOrders: int
    version: int
    createdAt: str
    updatedAt: str


class BusinessListResponse(BaseModel):
    data: list[BusinessResponse]
    pagination: PaginationResponse


class UserListResponse(BaseModel):
    data: list[AppUserResponse]
    pagination: PaginationResponse


class KitchenAccountInput(InputModel):
    email: str = Field(min_length=3, max_length=254)
    displayName: str = Field(min_length=1, max_length=160)
    password: str = Field(min_length=12, max_length=128, json_schema_extra={"writeOnly": True})


class CreateBusinessInput(InputModel):
    name: str = Field(min_length=1, max_length=160)
    category: str = Field(default="Cafetería", max_length=80)
    description: str = Field(default="", max_length=2000)
    imageUrl: str | None = Field(default=None, max_length=2048)
    timezone: str = Field(default="America/Mexico_City", max_length=80)
    account: KitchenAccountInput


class CreatedBusinessResponse(BaseModel):
    business: BusinessResponse
    user: AppUserResponse


class VersionInput(InputModel):
    expectedVersion: int | None = Field(default=None, ge=1, strict=True)


class UpdateBusinessInput(VersionInput):
    name: str | None = Field(default=None, min_length=1, max_length=160)
    category: str | None = Field(default=None, max_length=80)
    description: str | None = Field(default=None, max_length=2000)
    imageUrl: str | None = Field(default=None, max_length=2048)
    timezone: str | None = Field(default=None, max_length=80)


class UpdateAccountInput(VersionInput):
    displayName: str | None = Field(default=None, min_length=1, max_length=160)
    avatarUrl: str | None = Field(default=None, max_length=1000)
    isActive: bool | None = Field(default=None, strict=True)


def business_response(business: Business, db: Session) -> dict:
    from .v3_operations import business_dto
    return {**business_dto(business, db), "isActive": business.is_active}


def _revalidate_actor(request: Request, db: Session):
    actor = current_user(request, db)
    require(actor.role == "admin", 403, "FORBIDDEN", "Se requiere acceso administrativo.")
    return actor


def _lock_actor(actor: User, request: Request, db: Session):
    _lock_admins(db)
    actor = db.scalar(select(User).where(User.id == actor.id).with_for_update()
                      .execution_options(populate_existing=True))
    # The dependency may have authenticated before this User lock became
    # available. Observe a winning logout and recheck the JWT expiry as well.
    return _revalidate_actor(request, db)


def _timezone(value):
    try:
        ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError, TypeError):
        raise ApiError(422, "INVALID_TIMEZONE", "La zona horaria no es válida.") from None
    return value


@router.get("/admin/businesses", response_model=BusinessListResponse)
def list_businesses(page: int = Query(1, ge=1), limit: int = Query(20, ge=1, le=200),
                    q: str = Query("", max_length=160), includeInactive: bool = False,
                    actor: User = Depends(require_admin), db: Session = Depends(get_db, scope="function")):
    stmt = select(Business)
    if not includeInactive:
        stmt = stmt.where(Business.is_active.is_(True))
    if q.strip():
        value = q.strip().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        stmt = stmt.where(Business.name.ilike(f"%{value}%", escape="\\"))
    return page_result(db, stmt.order_by(Business.name, Business.id), lambda b: business_response(b, db), page, limit)


@router.get("/admin/businesses/{id}", response_model=BusinessResponse)
def get_business(id: str, actor: User = Depends(require_admin), db: Session = Depends(get_db, scope="function")):
    business = db.get(Business, id)
    require(business is not None, 404, "BUSINESS_NOT_FOUND", "El local no existe.")
    return business_response(business, db)


@router.post("/admin/businesses", status_code=201, response_model=CreatedBusinessResponse,
             description="Crea local cerrado y una cuenta COCINA en una transacción. Contraseña inicial explícita; no envía correo.")
def create_business(request: Request, data: CreateBusinessInput, actor: User = Depends(require_admin),
                    db: Session = Depends(get_db, scope="function")):
    actor = _lock_actor(actor, request, db)
    require(bool(data.name.strip()) and bool(data.account.displayName.strip()))
    require(data.imageUrl is None, 422, "IMAGE_REQUIRES_BUSINESS",
            "Crea el local y después sube y vincula su imagen autorizada.")
    email = normalize_email(data.account.email)
    require(db.scalar(select(User.id).where(User.email == email)) is None, 409,
            "EMAIL_EXISTS", "Ya existe una cuenta con ese correo.")
    settings = request.app.state.settings
    now = utcnow()
    business = Business(id=new_id(), name=data.name.strip(), category=data.category.strip(),
                        description=data.description.strip(), image_url=None,
                        timezone=_timezone(data.timezone), cafeteria_id=settings.cafeteria_id,
                        cafeteria_name=settings.cafeteria_name, is_active=True, is_open=False,
                        version=1, next_order_number=1, created_at=now, updated_at=now)
    db.add(business)
    db.flush()
    user = User(id=new_id(), email=email, display_name=data.account.displayName.strip(),
                password_hash=hash_password(data.account.password), role="business", business_id=business.id,
                is_active=True, is_master=False, approval_status="approved", email_verified=True,
                version=1, auth_version=1, created_at=now, updated_at=now)
    db.add(user)
    db.flush()
    actor = _revalidate_actor(request, db)
    audit_event(db, actor.id, "business.provisioned", "business", business.id, {"kitchenUserId": user.id})
    audit_event(db, actor.id, "kitchen.provisioned", "user", user.id, {"businessId": business.id})
    emit_event(db, "admin", "business.created", {"businessId": business.id, "version": business.version})
    return {"business": business_response(business, db), "user": serialize_v3_user(user, db)}


@router.patch("/admin/businesses/{id}", response_model=BusinessResponse)
def update_business(id: str, request: Request, data: UpdateBusinessInput, actor: User = Depends(require_admin),
                    db: Session = Depends(get_db, scope="function")):
    actor = _lock_actor(actor, request, db)
    business = db.scalar(select(Business).where(Business.id == id).with_for_update()
                         .execution_options(populate_existing=True))
    require(business is not None, 404, "BUSINESS_NOT_FOUND", "El local no existe.")
    require(business.is_active, 409, "BUSINESS_INACTIVE", "El local está desactivado.")
    if data.expectedVersion is not None:
        version_check(business, data.expectedVersion)
    fields = data.model_fields_set - {"expectedVersion"}
    require(bool(fields))
    for name in fields:
        value = getattr(data, name)
        if name == "imageUrl":
            from .v3_media import owned_media
            owned_media(db, actor, value, request.app.state.settings, purpose="business", business_id=business.id)
            business.image_url = value
        elif name == "timezone":
            business.timezone = _timezone(value)
        else:
            require(value is not None and (name != "name" or bool(value.strip())))
            setattr(business, name, value.strip())
    actor = _revalidate_actor(request, db)
    business.version += 1
    business.updated_at = utcnow()
    db.flush()
    audit_event(db, actor.id, "business.updated", "business", business.id, {"fields": sorted(fields)})
    emit_event(db, f"business:{business.id}", "business.updated", {"businessId": business.id, "version": business.version})
    return business_response(business, db)


@router.delete("/admin/businesses/{id}", status_code=204)
def deactivate_business(id: str, request: Request, data: VersionInput | None = Body(default=None),
                        actor: User = Depends(require_admin), db: Session = Depends(get_db, scope="function")):
    actor = _lock_actor(actor, request, db)
    # User before Business follows the order used by kitchen writes. Locking
    # the business before its operator would deadlock with an in-flight order.
    operators = list(db.scalars(select(User).where(User.business_id == id, User.role == "business")
                                .order_by(User.id).with_for_update().execution_options(populate_existing=True)))
    business = db.scalar(select(Business).where(Business.id == id).with_for_update()
                         .execution_options(populate_existing=True))
    require(business is not None, 404, "BUSINESS_NOT_FOUND", "El local no existe.")
    if data and data.expectedVersion is not None:
        version_check(business, data.expectedVersion)
    active = db.scalar(select(Order.id).where(Order.business_id == id,
                       Order.status.in_(("pending", "accepted", "preparing", "ready"))).limit(1))
    require(active is None, 409, "BUSINESS_HAS_ACTIVE_ORDERS", "Resuelve los pedidos activos antes de desactivar el local.")
    actor = _revalidate_actor(request, db)
    if business.is_active:
        business.is_active = business.is_open = False
        business.version += 1
        business.updated_at = utcnow()
        families = set()
        for user in operators:
            user.is_active = False
            user.version += 1
            revoke_user_sessions(db, user)
            families.update(db.scalars(select(RefreshSession.family_id).where(RefreshSession.user_id == user.id)))
        from .push import detach_devices_for_families
        detach_devices_for_families(db, families)
        audit_event(db, actor.id, "business.deactivated", "business", business.id)
        emit_event(db, f"business:{business.id}", "business.updated", {"businessId": business.id, "version": business.version})
    return Response(status_code=204)


@router.get("/admin/users", response_model=UserListResponse)
def list_users(page: int = Query(1, ge=1), limit: int = Query(20, ge=1, le=200),
               q: str = Query("", max_length=160), role: Literal["ALUMNO", "COCINA", "ADMIN"] | None = None,
               actor: User = Depends(require_admin), db: Session = Depends(get_db, scope="function")):
    stmt = select(User).where(User.role.in_(("user", "business", "admin")))
    # Ordinary administration does not enumerate other administrative accounts.
    if not actor.is_master:
        stmt = stmt.where(or_(User.role != "admin", User.id == actor.id))
    if role:
        stmt = stmt.where(User.role == {"ALUMNO": "user", "COCINA": "business", "ADMIN": "admin"}[role])
    if q.strip():
        value = q.strip().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        stmt = stmt.where(or_(User.display_name.ilike(f"%{value}%", escape="\\"),
                              User.email.ilike(f"%{value}%", escape="\\")))
    return page_result(db, stmt.order_by(User.created_at.desc(), User.id), lambda u: serialize_v3_user(u, db), page, limit)


@router.patch("/admin/users/{id}", response_model=AppUserResponse,
              description="Edita nombre/avatar o suspende/reactiva ALUMNO/COCINA sin cambiar rol ni negocio.")
def update_user(id: str, request: Request, data: UpdateAccountInput, actor: User = Depends(require_admin),
                db: Session = Depends(get_db, scope="function")):
    actor = _lock_actor(actor, request, db)
    user = db.scalar(select(User).where(User.id == id).with_for_update()
                     .execution_options(populate_existing=True))
    require(user is not None, 404, "USER_NOT_FOUND", "La cuenta no existe.")
    require(user.role in ("user", "business") and not user.is_master, 403, "PROTECTED_ACCOUNT",
            "Esta ruta solo administra cuentas de alumno o Cocina.")
    if data.expectedVersion is not None:
        version_check(user, data.expectedVersion)
    fields = data.model_fields_set - {"expectedVersion"}
    require(bool(fields))
    if "isActive" in fields:
        require(data.isActive is not None)
        if data.isActive:
            record = db.scalar(select(AcademicRecord).where(AcademicRecord.email == user.email)
                               .execution_options(populate_existing=True))
            require(record is None or record.is_active, 403, "ACCESS_REVOKED", "El padrón no autoriza esta cuenta.")
            if user.role == "user":
                require(record is not None and record.kind == "student", 403, "ACCESS_REVOKED")
            else:
                business = db.scalar(select(Business).where(Business.id == user.business_id).with_for_update())
                require(business is not None and business.is_active, 409, "BUSINESS_INACTIVE")
                other = db.scalar(select(User.id).where(User.business_id == user.business_id,
                                  User.role == "business", User.is_active.is_(True),
                                  User.approval_status == "approved", User.id != user.id).limit(1))
                require(other is None, 409, "BUSINESS_ALREADY_ASSIGNED")
        user.is_active = data.isActive
    if "displayName" in fields:
        require(data.displayName is not None and bool(data.displayName.strip()))
        user.display_name = data.displayName.strip()
    if "avatarUrl" in fields:
        from .v3_media import owned_media
        owned_media(db, user, data.avatarUrl, request.app.state.settings, purpose="avatar")
        user.avatar_url = data.avatarUrl
    actor = _revalidate_actor(request, db)
    user.version += 1
    user.updated_at = utcnow()
    revoke_user_sessions(db, user)
    from .push import detach_devices_for_families
    families = set(db.scalars(select(RefreshSession.family_id).where(RefreshSession.user_id == user.id)))
    detach_devices_for_families(db, families, user_id=user.id)
    db.flush()
    audit_event(db, actor.id, "account.updated", "user", user.id, {"fields": sorted(fields), "isActive": user.is_active})
    return serialize_v3_user(user, db)


@router.post("/admin/users/{id}/reset-password", status_code=204)
def initiate_password_reset(id: str, request: Request, actor: User = Depends(require_admin),
                            db: Session = Depends(get_db, scope="function")):
    actor = _lock_actor(actor, request, db)
    user = db.scalar(select(User).where(User.id == id).with_for_update()
                     .execution_options(populate_existing=True))
    require(user is not None, 404, "USER_NOT_FOUND", "La cuenta no existe.")
    require(user.role in ("user", "business") and not user.is_master, 403, "PROTECTED_ACCOUNT")
    settings = request.app.state.settings
    require(mail_available(settings), 503, "EMAIL_UNAVAILABLE", "La recuperación requiere envío de correo configurado.")
    actor = _revalidate_actor(request, db)
    _mail_token(db, user, settings, "reset", getattr(request.app.state, "mailer", None))
    audit_event(db, actor.id, "password.reset_requested", "user", user.id)
    return Response(status_code=204)
