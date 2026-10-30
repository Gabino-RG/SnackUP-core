"""Canonical V3 DTOs/routes, backed by the existing transactional services.

Public IDs stay opaque. The explicitly versioned legacy adapter shares the same
rows, reservations and state machine; neither API can double-reserve or deliver.
"""
from .auth import request_user

from datetime import date, datetime, timezone
from decimal import Decimal, InvalidOperation
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Body, Depends, Header, Query, Request, Response
from pydantic import AwareDatetime, BaseModel, BeforeValidator, ConfigDict, Field, StrictBool, StrictInt, create_model, model_validator
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .admin_models import Review
from .auth import current_user, require_business, require_student
from .common import iso, require
from .db import emit_event, get_db, new_id, utcnow
from .errors import ApiError
from .identity_models import User
from .operation_models import Business, Order, OrderItem, Product
from .operations import (
    ACTIVE, _business, _history_filter, _order, _product, _product_event,
    _range, _summary, _touch, check_optional_version, create_order_transaction,
    effective_availability, transition,
)
from .review_models import ProductReview
from .v3_media import owned_media

router = APIRouter()
DB = Annotated[Session, Depends(get_db, scope="function")]
Authenticated = Annotated[User, Depends(request_user)]
Operator = Annotated[User, Depends(require_business)]
Student = Annotated[User, Depends(require_student)]
Page = Annotated[int, Query(ge=1)]
Limit = Annotated[int, Query(ge=1, le=200)]
PUBLIC_ROLES = {"user": "ALUMNO", "business": "COCINA", "admin": "ADMIN"}
KITCHEN_REASONS = frozenset({"product_unavailable", "cannot_prepare", "store_issue", "store_closing", "other", "not_picked_up"})
# V2 was not supplied. This is the only student reason explicitly named in V3;
# expanding this catalog requires the actual V2 contract, never a wildcard.
STUDENT_REASONS = frozenset({"user_other"})


def _money(value):
    if type(value) not in (int, float, Decimal):
        raise ValueError("El importe debe ser un número JSON.")
    try:
        amount = Decimal(str(value))
        if not amount.is_finite() or amount != amount.quantize(Decimal("0.01")):
            raise ValueError("El importe admite dos decimales.")
        return amount
    except InvalidOperation as error:
        raise ValueError("Importe inválido.") from error


Money = Annotated[Decimal, BeforeValidator(_money, json_schema_input_type=float)]
OpaqueId = Annotated[str, Field(min_length=1, max_length=1500)]


class StrictInput(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


class OrderItemInput(StrictInput):
    productId: OpaqueId
    quantity: StrictInt = Field(ge=1, le=99)
    notes: str = Field(default="", max_length=500)


class CreateOrderInput(StrictInput):
    businessId: OpaqueId
    items: list[OrderItemInput] = Field(min_length=1, max_length=50)
    paymentMethod: Literal["Efectivo", "Transferencia", "Tarjeta", "ValeComida"] = "Efectivo"
    expectedTotal: Money = Field(ge=0, le=50_000_000,
                                json_schema_extra={"minimum": 0, "maximum": 50_000_000, "multipleOf": 0.01})
    scheduledPickupTime: AwareDatetime | None = Field(default=None, strict=False)

    @model_validator(mode="before")
    @classmethod
    def validate_items_and_schedule(cls, value):
        if not isinstance(value, dict):
            return value
        schedule = value.get("scheduledPickupTime")
        if schedule is not None and not isinstance(schedule, str):
            raise ApiError(422, "INVALID_SCHEDULE", "Envía una fecha ISO 8601 con zona horaria.")
        items = value.get("items")
        if not isinstance(items, list) or not items or any(
            not isinstance(item, dict) or type(item.get("quantity")) is not int or item["quantity"] < 1
            for item in items
        ):
            raise ApiError(400, "INVALID_ITEMS", "El carrito debe contener productos con cantidades enteras positivas.")
        return value


class VersionInput(StrictInput):
    expectedVersion: StrictInt | None = Field(default=None, ge=1)

    @model_validator(mode="before")
    @classmethod
    def reject_null_version(cls, value):
        if isinstance(value, dict) and "expectedVersion" in value and value["expectedVersion"] is None:
            raise ValueError("Omite expectedVersion o envía un entero positivo.")
        return value


class CompleteInput(VersionInput):
    method: Literal["qr", "manual"]
    code: str = Field(min_length=1, max_length=128)


class CancelInput(VersionInput):
    reason: str = Field(min_length=1, max_length=60)
    voucherNotRedeemed: StrictBool = False
    notes: str = Field(default="", max_length=500)


class ProductCreate(StrictInput):
    name: str = Field(min_length=1, max_length=160)
    description: str | None = Field(default="", max_length=2000)
    category: str = Field(min_length=1, max_length=120)
    subcategory: str | None = Field(default=None, max_length=80)
    price: Money = Field(ge=Decimal("0.01"), le=10000,
                         json_schema_extra={"minimum": 0.01, "maximum": 10000, "multipleOf": 0.01})
    stock: StrictInt | None = Field(default=None, ge=0, le=1_000_000)
    imageUrl: str | None = Field(default=None, max_length=2048)
    isAvailable: StrictBool = True
    isFeatured: StrictBool = False
    preparationMinutes: StrictInt | None = Field(default=None, ge=0, le=1440)
    calories: StrictInt | None = Field(default=None, ge=0, le=100_000)


class ProductPatch(VersionInput):
    name: str | None = Field(default=None, min_length=1, max_length=160)
    description: str | None = Field(default=None, max_length=2000)
    category: str | None = Field(default=None, min_length=1, max_length=120)
    subcategory: str | None = Field(default=None, max_length=80)
    price: Money | None = Field(default=None, ge=Decimal("0.01"), le=10000,
                                json_schema_extra={"minimum": 0.01, "maximum": 10000, "multipleOf": 0.01})
    stock: StrictInt | None = Field(default=None, ge=0, le=1_000_000)
    imageUrl: str | None = Field(default=None, max_length=2048)
    isAvailable: StrictBool | None = None
    isFeatured: StrictBool | None = None
    preparationMinutes: StrictInt | None = Field(default=None, ge=0, le=1440)
    calories: StrictInt | None = Field(default=None, ge=0, le=100_000)


class AvailabilityInput(VersionInput):
    isAvailable: StrictBool


class BusinessStatusInput(VersionInput):
    isOpen: StrictBool


class BusinessPatch(VersionInput):
    coverImageUrl: str | None = Field(default=None, max_length=2048)
    pickupTimeoutMinutes: StrictInt | None = Field(default=None, ge=5, le=180)
    name: str | None = Field(default=None, min_length=1, max_length=160)
    category: str | None = Field(default=None, max_length=80)
    description: str | None = Field(default=None, max_length=2000)
    imageUrl: str | None = Field(default=None, max_length=2048)


class ResponseModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class PaginationResponse(ResponseModel):
    page: int
    limit: int
    total: int
    totalPages: int


class BusinessResponse(ResponseModel):
    coverImageUrl: str | None
    pickupTimeoutMinutes: int
    autoCloseEnabled: bool
    closeTimeLocal: str | None
    postponedCloseAt: datetime | None
    lastAutoCloseDate: date | None
    id: str
    name: str
    category: str
    description: str
    imageUrl: str | None
    ownerId: str | None
    isOpen: bool
    isActive: bool
    timezone: str
    averageRating: float
    totalRatings: int
    totalOrders: int
    version: int
    createdAt: datetime
    updatedAt: datetime


class BusinessPageResponse(ResponseModel):
    data: list[BusinessResponse]
    pagination: PaginationResponse


class ProductResponse(ResponseModel):
    id: str
    businessId: str
    name: str
    description: str
    category: str
    subcategory: str | None
    price: float
    stock: int | None
    imageUrl: str | None
    isAvailable: bool
    isFeatured: bool
    preparationMinutes: int | None
    calories: int | None
    averageRating: float
    totalReviews: int
    version: int
    createdAt: datetime
    updatedAt: datetime


# The fields query projects a real subset. No absent property is synthesized in
# the response; the full DTO remains separately documented for detail/CRUD.
ProductProjectionResponse = create_model(
    "ProductProjectionResponse", __base__=ResponseModel,
    **{name: (field.annotation, None) for name, field in ProductResponse.model_fields.items()},
)


class ProductPageResponse(ResponseModel):
    data: list[ProductResponse | ProductProjectionResponse]
    pagination: PaginationResponse


class OrderItemResponse(ResponseModel):
    id: str
    productId: str
    name: str
    price: float
    quantity: int
    notes: str


class VerificationResponse(ResponseModel):
    method: Literal["qr", "manual"]
    verifiedAt: datetime | None
    verifiedBy: str | None


class OrderResponse(ResponseModel):
    id: str
    orderNumber: int
    businessId: str
    customerName: str
    items: list[OrderItemResponse]
    subtotal: float
    total: float
    paymentMethod: Literal["Efectivo", "Transferencia", "Tarjeta", "ValeComida"]
    paymentStatus: str
    status: Literal["pending", "accepted", "preparing", "ready", "completed", "cancelled"]
    createdAt: datetime
    updatedAt: datetime
    acceptedAt: datetime | None
    preparingAt: datetime | None
    readyAt: datetime | None
    completedAt: datetime | None
    cancelledAt: datetime | None
    scheduledPickupTime: datetime | None
    cancelReason: str | None
    cancelNotes: str | None
    cancelledBy: Literal["ALUMNO", "COCINA", "ADMIN"] | None
    verification: VerificationResponse | None
    isRated: bool
    version: int
    # These properties are present only for the student who owns the order.
    # exclude_unset on every order route is part of this privacy contract.
    userId: str | None = None
    customerNumeroDeControl: str | None = None
    pickupCode: str | None = None


class OrderPageResponse(ResponseModel):
    data: list[OrderResponse]
    pagination: PaginationResponse


class SalesSummaryResponse(ResponseModel):
    completed: int
    cancelled: int
    totalSold: float


class DailySales(ResponseModel):
    date: date
    completed: int
    cancelled: int
    totalSold: float


class TopProduct(ResponseModel):
    productId: str
    name: str
    quantity: int
    totalSold: float


class PaymentSales(ResponseModel):
    paymentMethod: str
    completed: int
    totalSold: float


class DetailedSalesResponse(SalesSummaryResponse):
    timezone: str
    daily: list[DailySales]
    topProducts: list[TopProduct]
    paymentMethods: list[PaymentSales]


class OrderHistoryResponse(OrderPageResponse):
    summary: SalesSummaryResponse


def _business_aggregates(db: Session, ids) -> dict:
    ids = list(ids)
    result = {id: {"ownerId": None, "averageRating": 0.0, "totalRatings": 0} for id in ids}
    if not ids:
        return result
    for business_id, average, count in db.execute(
        select(Review.business_id, func.avg(Review.rating), func.count(Review.rating))
        .where(Review.business_id.in_(ids)).group_by(Review.business_id)
    ):
        result[business_id].update(averageRating=round(float(average or 0), 2), totalRatings=count)
    for business_id, owner_id in db.execute(select(User.business_id, User.id).where(
        User.business_id.in_(ids), User.role == "business", User.is_active.is_(True), User.approval_status == "approved"
    )):
        result[business_id]["ownerId"] = owner_id
    return result


def business_dto(b: Business, db: Session, *, aggregates=None) -> dict:
    aggregate = (aggregates if aggregates is not None else _business_aggregates(db, [b.id]))[b.id]
    # Every order is created through the atomic counter UPDATE in the same
    # transaction and orders are never deleted, so the counter is the count;
    # COUNT(*) over a semester of orders on every catalog read is not needed.
    aggregate = {**aggregate, "totalOrders": b.next_order_number - 1}
    return {"id": b.id, "name": b.name, "category": b.category, "description": b.description,
            "imageUrl": b.image_url, "coverImageUrl": b.cover_image_url,
            "pickupTimeoutMinutes": b.pickup_timeout_minutes, "autoCloseEnabled": b.auto_close_enabled,
            "closeTimeLocal": b.close_time_local, "postponedCloseAt": iso(b.postponed_close_at),
            "lastAutoCloseDate": b.last_auto_close_date, "isOpen": b.is_open, "isActive": b.is_active, "timezone": b.timezone,
            "version": b.version, "createdAt": iso(b.created_at), "updatedAt": iso(b.updated_at), **aggregate}


def _product_aggregates(db: Session, ids) -> dict:
    ids = list(ids)
    result = {id: {"averageRating": 0.0, "totalReviews": 0} for id in ids}
    if ids:
        for product_id, average, count in db.execute(
            select(ProductReview.product_id, func.avg(ProductReview.rating), func.count())
            .where(ProductReview.product_id.in_(ids)).group_by(ProductReview.product_id)
        ):
            result[product_id].update(averageRating=round(float(average or 0), 2), totalReviews=count)
    return result


def product_dto(p: Product, db: Session, *, aggregates=None) -> dict:
    aggregate = (aggregates if aggregates is not None else _product_aggregates(db, [p.id]))[p.id]
    return {"id": p.id, "businessId": p.business_id, "name": p.name, "description": p.description,
            "category": p.category, "subcategory": p.subcategory, "price": float(p.price),
            "stock": p.stock, "imageUrl": p.image_url, "isAvailable": effective_availability(p),
            "isFeatured": p.is_featured, "preparationMinutes": p.preparation_minutes, "calories": p.calories,
            "version": p.version, "createdAt": iso(p.created_at), "updatedAt": iso(p.updated_at), **aggregate}


def order_dto(o: Order, db: Session, actor: User, *, rated_ids=None) -> dict:
    owner = actor.role == "user" and o.student_id == actor.id
    if rated_ids is None:
        is_rated = db.scalar(select(Review.id).where(Review.order_id == o.id)) is not None
    else:
        is_rated = o.id in rated_ids
    result = {"id": o.id, "orderNumber": o.order_number, "businessId": o.business_id,
              "customerName": o.customer_name,
              "items": [{"id": x.id, "productId": x.product_id, "name": x.name,
                         "price": float(x.price), "quantity": x.quantity, "notes": x.notes} for x in o.items],
              "subtotal": float(o.subtotal if o.subtotal is not None else o.total), "total": float(o.total),
              "paymentMethod": "Efectivo" if o.payment_method == "cash" else o.payment_method,
              "paymentStatus": o.payment_status, "status": o.status, "cancelReason": o.cancel_reason,
              "cancelNotes": o.cancel_notes, "cancelledBy": o.cancelled_by_role or (
                  "ALUMNO" if o.cancelled_by == o.student_id else "COCINA"
              ) if o.cancelled_by else None,
              "verification": {"method": o.verification_method, "verifiedAt": iso(o.verified_at or o.completed_at),
                               "verifiedBy": o.verified_by} if o.verification_method else None,
              "isRated": is_rated, "version": o.version}
    for key, attr in (("createdAt", "created_at"), ("updatedAt", "updated_at"),
                      ("acceptedAt", "accepted_at"), ("preparingAt", "preparing_at"),
                      ("readyAt", "ready_at"), ("completedAt", "completed_at"),
                      ("cancelledAt", "cancelled_at"), ("scheduledPickupTime", "scheduled_pickup_time")):
        result[key] = iso(getattr(o, attr))
    if owner:
        result.update(userId=o.student_id, customerNumeroDeControl=o.customer_institutional_id, pickupCode=o.pickup_code)
    return result


def _page_rows(db, statement, page, limit):
    total = db.scalar(select(func.count()).select_from(statement.order_by(None).subquery())) or 0
    rows = db.scalars(statement.offset((page - 1) * limit).limit(limit)).all()
    return rows, {"page": page, "limit": limit, "total": total, "totalPages": (total + limit - 1) // limit}


def _orders_page(db, statement, actor, page, limit):
    rows, pagination = _page_rows(db, statement, page, limit)
    rated = set(db.scalars(select(Review.order_id).where(Review.order_id.in_([row.id for row in rows])))) if rows else set()
    return {"data": [order_dto(row, db, actor, rated_ids=rated) for row in rows], "pagination": pagination}


def _catalog_business(db: Session, actor: User, id: str) -> Business:
    require(actor.role in PUBLIC_ROLES, 403, "FORBIDDEN")
    if actor.role == "business":
        return _business(db, actor, id)
    b = db.get(Business, id)
    require(b is not None and (b.is_active or actor.role == "admin"), 404, "NOT_FOUND", "Local no encontrado.")
    return b


def _lock_catalog_actor(db: Session, request: Request, actor: User) -> User:
    db.scalar(select(User).where(User.id == actor.id).with_for_update()
              .execution_options(populate_existing=True))
    return require_business(current_user(request, db))


def _business_for_write(db: Session, request: Request, actor: User, id: str) -> Business:
    actor = _lock_catalog_actor(db, request, actor)
    business = _business(db, actor, id, lock=True)
    require_business(current_user(request, db))
    return business


def _product_for_write(db: Session, request: Request, actor: User, id: str) -> Product:
    # Keep the User -> Business -> Product order used by order creation. A
    # revoked/expired session must be observed after waiting for either row.
    actor = _lock_catalog_actor(db, request, actor)
    _business(db, actor, actor.business_id, lock=True)
    product = _product(db, actor, id, lock=True)
    require_business(current_user(request, db))
    return product


def _valid_media(db: Session, request: Request, url: str | None, business_id: str, purpose: str) -> None:
    # Business/product media is scoped by its business. The shared validator
    # locks the media row so attachment cannot race its physical deletion.
    owned_media(db, None, url, request.app.state.settings, purpose=purpose, business_id=business_id)


def _apply_product_changes(db: Session, request: Request, product: Product, changes: dict) -> None:
    for key in ("name", "category", "price", "isAvailable", "isFeatured"):
        require(key not in changes or changes[key] is not None, 422, "INVALID_INPUT", f"{key} no admite null.")
    for key in ("name", "category"):
        if key in changes:
            require(bool(changes[key].strip()), 422, "INVALID_INPUT", f"{key} no puede estar vacío.")
    from .v32_services import enforce_featured_limit
    if "isFeatured" in changes:
        enforce_featured_limit(db, product.business_id, changes["isFeatured"], product.id)
    if "imageUrl" in changes:
        _valid_media(db, request, changes["imageUrl"], product.business_id, "product")
    if "stock" in changes and changes["stock"] is not None and product.id:
        reserved = db.scalar(select(func.coalesce(func.sum(OrderItem.reserved_quantity), 0))
                             .join(Order, Order.id == OrderItem.order_id).where(
                                 OrderItem.product_id == product.id, Order.status.in_(ACTIVE),
                                 Order.stock_restored.is_(False)))
        require(changes["stock"] + reserved <= 1_000_000, 422, "INVALID_STOCK",
                "El inventario y sus reservas exceden el máximo permitido.")
    # Media attachment can also wait on a row lock. Recheck before changing
    # any attributes, so no autoflush precedes the final authorization check.
    require_business(current_user(request, db))
    fields = {"name": "name", "description": "description", "category": "category", "subcategory": "subcategory",
              "price": "price", "stock": "stock", "imageUrl": "image_url", "isFeatured": "is_featured",
              "isAvailable": "manual_available", "preparationMinutes": "preparation_minutes", "calories": "calories"}
    for key, attr in fields.items():
        if key in changes:
            value = changes[key]
            if key in ("name", "description", "category", "subcategory") and isinstance(value, str):
                value = value.strip()
            if key == "description" and value is None:
                value = ""
            setattr(product, attr, value)
    product.is_available = effective_availability(product)


@router.get("/businesses", operation_id="v3ListBusinesses", response_model=BusinessPageResponse)
def list_businesses(db: DB, actor: Authenticated, page: Page = 1, limit: Limit = 20,
                    isOpen: bool | None = None, category: str | None = None):
    require(actor.role in PUBLIC_ROLES, 403, "FORBIDDEN")
    statement = select(Business)
    if actor.role == "business":
        statement = statement.where(Business.id == actor.business_id, Business.is_active.is_(True))
    elif actor.role != "admin":
        statement = statement.where(Business.is_active.is_(True))
    if isOpen is not None:
        statement = statement.where(Business.is_open == isOpen)
    if category is not None:
        statement = statement.where(Business.category == category)
    rows, pagination = _page_rows(db, statement.order_by(Business.name, Business.id), page, limit)
    aggregates = _business_aggregates(db, [row.id for row in rows])
    return {"data": [business_dto(row, db, aggregates=aggregates) for row in rows], "pagination": pagination}


@router.get("/businesses/{id}", operation_id="v3GetBusiness", response_model=BusinessResponse)
def get_business(id: str, db: DB, actor: Authenticated):
    return business_dto(_catalog_business(db, actor, id), db)


@router.patch("/businesses/{id}", operation_id="v3UpdateBusinessProfile", response_model=BusinessResponse)
def update_business(id: str, body: BusinessPatch, request: Request, db: DB, actor: Operator):
    business = _business_for_write(db, request, actor, id)
    changes = body.model_dump(exclude_unset=True)
    check_optional_version(business, changes)
    if "imageUrl" in changes:
        _valid_media(db, request, changes["imageUrl"], id, "business")
        require_business(current_user(request, db))
    for field in ("name", "category", "description"):
        if field in changes:
            require(isinstance(changes[field], str), 422, "INVALID_INPUT", f"{field} debe ser texto.")
            if field == "name":
                require(bool(changes[field].strip()), 422, "INVALID_INPUT", "El nombre no puede estar vacío.")
            setattr(business, field, changes[field].strip())
    if "imageUrl" in changes:
        business.image_url = changes["imageUrl"]
    if "coverImageUrl" in changes:
        _valid_media(db, request, changes["coverImageUrl"], id, "business")
        require_business(current_user(request, db))
        business.cover_image_url = changes["coverImageUrl"]
    if "pickupTimeoutMinutes" in changes:
        require(changes["pickupTimeoutMinutes"] is not None, 422, "INVALID_INPUT")
        business.pickup_timeout_minutes = changes["pickupTimeoutMinutes"]
    _touch(business)
    emit_event(db, f"business:{id}", "business.updated", {"id": id, "version": business.version,
               "updatedAt": iso(business.updated_at), "isOpen": business.is_open})
    return business_dto(business, db)


@router.patch("/businesses/{id}/status", operation_id="v3SetBusinessOpen", response_model=BusinessResponse)
def set_business_open(id: str, body: BusinessStatusInput, request: Request, db: DB, actor: Operator):
    business = _business_for_write(db, request, actor, id)
    check_optional_version(business, body.model_dump(exclude_unset=True))
    from .v32_services import notify_business_closed
    if business.is_open and not body.isOpen:
        notify_business_closed(db, business)
    business.is_open = body.isOpen
    _touch(business)
    emit_event(db, f"business:{id}", "business.updated", {"id": id, "version": business.version,
               "updatedAt": iso(business.updated_at), "isOpen": business.is_open})
    return business_dto(business, db)


@router.get("/businesses/{id}/products", operation_id="v3ListProducts",
            response_model=ProductPageResponse, response_model_exclude_unset=True)
def list_products(id: str, db: DB, actor: Authenticated, page: Page = 1, limit: Limit = 20,
                  fields: str | None = None, isAvailable: bool | None = None, category: str | None = None, q: str = ""):
    _catalog_business(db, actor, id)
    statement = select(Product).where(Product.business_id == id, Product.is_deleted.is_(False))
    if isAvailable is not None:
        statement = statement.where(Product.is_available == isAvailable)
    if category is not None:
        statement = statement.where(Product.category == category)
    if q:
        search = q.strip().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        statement = statement.where(Product.name.ilike(f"%{search}%", escape="\\"))
    rows, pagination = _page_rows(db, statement.order_by(Product.category, Product.name, Product.id), page, limit)
    aggregates = _product_aggregates(db, [row.id for row in rows])
    data = [product_dto(row, db, aggregates=aggregates) for row in rows]
    if fields is not None:
        allowed = {"id", "businessId", "name", "description", "category", "subcategory", "price", "stock",
                   "imageUrl", "isAvailable", "isFeatured", "preparationMinutes", "calories", "version", "createdAt",
                   "updatedAt", "averageRating", "totalReviews"}
        selected = set(fields.split(","))
        require(bool(selected) and selected <= allowed, 422, "INVALID_FIELDS", "Se solicitaron campos no disponibles.")
        data = [{key: value for key, value in row.items() if key in selected} for row in data]
    return {"data": data, "pagination": pagination}


@router.get("/products/{id}", operation_id="v3GetProduct", response_model=ProductResponse)
def get_product(id: str, db: DB, actor: Authenticated):
    product = db.get(Product, id)
    require(product is not None and not product.is_deleted, 404, "NOT_FOUND", "Producto no encontrado.")
    _catalog_business(db, actor, product.business_id)
    return product_dto(product, db)


@router.post("/businesses/{id}/products", status_code=201, operation_id="v3CreateProduct", response_model=ProductResponse)
def create_product(id: str, body: ProductCreate, request: Request, db: DB, actor: Operator):
    _business_for_write(db, request, actor, id)
    product = Product(id=new_id(), business_id=id, version=1, is_deleted=False,
                      manual_available=True, stock=None, created_at=utcnow(), updated_at=utcnow())
    _apply_product_changes(db, request, product, body.model_dump())
    db.add(product)
    db.flush()
    _product_event(db, product)
    return product_dto(product, db)


@router.patch("/products/{id}", operation_id="v3UpdateProduct", response_model=ProductResponse)
def update_product(id: str, body: ProductPatch, request: Request, db: DB, actor: Operator):
    product = _product_for_write(db, request, actor, id)
    changes = body.model_dump(exclude_unset=True)
    check_optional_version(product, changes)
    _apply_product_changes(db, request, product, changes)
    _touch(product)
    db.flush()
    _product_event(db, product)
    return product_dto(product, db)


@router.patch("/products/{id}/availability", operation_id="v3SetProductAvailability", response_model=ProductResponse)
def set_availability(id: str, body: AvailabilityInput, request: Request, db: DB, actor: Operator):
    product = _product_for_write(db, request, actor, id)
    check_optional_version(product, body.model_dump(exclude_unset=True))
    product.manual_available = body.isAvailable
    product.is_available = effective_availability(product)
    _touch(product)
    db.flush()
    _product_event(db, product)
    return product_dto(product, db)


@router.delete("/products/{id}", status_code=204, operation_id="v3DeleteProduct")
def delete_product(id: str, request: Request, db: DB, actor: Operator, body: VersionInput = Body(default_factory=VersionInput)):
    product = _product_for_write(db, request, actor, id)
    check_optional_version(product, body.model_dump(exclude_unset=True))
    product.is_deleted, product.is_available, product.deleted_at = True, False, utcnow()
    _touch(product)
    _product_event(db, product)
    return Response(status_code=204)


@router.post("/orders", status_code=201, operation_id="v3CreateOrder",
             response_model=OrderResponse, response_model_exclude_unset=True)
def create_order(body: CreateOrderInput, request: Request, db: DB, actor: Student,
                 idempotency_key: Annotated[str, Header(alias="Idempotency-Key", min_length=32, max_length=36)]):
    try:
        key = str(UUID(idempotency_key))
    except (ValueError, AttributeError):
        raise ApiError(422, "INVALID_IDEMPOTENCY_KEY", "Idempotency-Key debe contener un UUID.") from None
    # A newly created pending order cannot have a review. Avoid querying that
    # table while the purchase still owns its stock and numbering locks.
    return create_order_transaction(body, request, db, actor, key, canonical=True,
                                    serializer=lambda order, session, user: order_dto(order, session, user, rated_ids=set()))


@router.get("/orders/{id}", operation_id="v3GetOrder",
            response_model=OrderResponse, response_model_exclude_unset=True)
def get_order(id: str, db: DB, actor: Authenticated):
    require(actor.role in ("user", "business"), 403, "FORBIDDEN")
    return order_dto(_order(db, actor, id, student=actor.role == "user"), db, actor)


def _updated_since(value: datetime | None):
    if value is not None:
        require(value.tzinfo is not None, 422, "INVALID_TIME", "updatedSince debe incluir una zona horaria UTC.")
        return value.astimezone(timezone.utc)
    return None


@router.get("/users/me/orders/active", operation_id="v3MyActiveOrders",
            response_model=OrderPageResponse, response_model_exclude_unset=True)
def my_active_orders(db: DB, actor: Student, page: Page = 1, limit: Limit = 20, updatedSince: datetime | None = None):
    since = _updated_since(updatedSince)
    statement = select(Order).where(Order.student_id == actor.id)
    statement = statement.where(Order.updated_at >= since) if since else statement.where(Order.status.in_(ACTIVE))
    return _orders_page(db, statement.order_by(Order.updated_at, Order.id), actor, page, limit)


@router.get("/businesses/{id}/orders/active", operation_id="v3ActiveOrders",
            response_model=OrderPageResponse, response_model_exclude_unset=True)
def active_orders(id: str, db: DB, actor: Operator, page: Page = 1, limit: Limit = 20, updatedSince: datetime | None = None):
    _business(db, actor, id)
    since = _updated_since(updatedSince)
    statement = select(Order).where(Order.business_id == id)
    # Deltas include terminal transitions so reconnecting kanbans remove cards.
    statement = statement.where(Order.updated_at >= since) if since else statement.where(Order.status.in_(ACTIVE))
    return _orders_page(db, statement.order_by(Order.updated_at, Order.id), actor, page, limit)


@router.get("/businesses/{id}/orders/history", operation_id="v3OrderHistory",
            response_model=OrderHistoryResponse, response_model_exclude_unset=True)
def order_history(id: str, date: date, db: DB, actor: Operator, page: Page = 1, limit: Limit = 20):
    business = _business(db, actor, id)
    start, end = _range(date, date, business.timezone)
    condition = _history_filter(id, start, end)
    statement = select(Order).where(condition).order_by(func.coalesce(Order.completed_at, Order.cancelled_at).desc(), Order.id)
    result = _orders_page(db, statement, actor, page, limit)
    result["summary"] = _summary(db, condition)
    return result


@router.get("/businesses/{id}/stats", operation_id="v3SalesSummary", response_model=DetailedSalesResponse)
def sales_summary(id: str, db: DB, actor: Operator, from_date: Annotated[date, Query(alias="from")], to: date):
    business = _business(db, actor, id)
    start, end = _range(from_date, to, business.timezone)
    from .v32_stats import detailed_summary
    return detailed_summary(db, business, start, end)


def _transition_response(db, actor, id, action, body, request):
    result = transition(db, actor, id, action, body.model_dump(exclude_unset=True), request,
                        student=actor.role == "user", canonical=True)
    # Every valid transition starts from an uncompleted order. A rating cannot
    # exist before this transition commits, including a fresh completion.
    response = order_dto(result, db, actor, rated_ids=set())
    db.commit()
    return response


@router.post("/orders/{id}/accept", operation_id="v3AcceptOrder",
             response_model=OrderResponse, response_model_exclude_unset=True)
def accept_order(id: str, request: Request, db: DB, actor: Operator, body: VersionInput = Body(default_factory=VersionInput)):
    return _transition_response(db, actor, id, "accept", body, request)


@router.post("/orders/{id}/start", operation_id="v3StartOrder",
             response_model=OrderResponse, response_model_exclude_unset=True)
def start_order(id: str, request: Request, db: DB, actor: Operator, body: VersionInput = Body(default_factory=VersionInput)):
    return _transition_response(db, actor, id, "start", body, request)


@router.post("/orders/{id}/ready", operation_id="v3ReadyOrder",
             response_model=OrderResponse, response_model_exclude_unset=True)
def ready_order(id: str, request: Request, db: DB, actor: Operator, body: VersionInput = Body(default_factory=VersionInput)):
    return _transition_response(db, actor, id, "ready", body, request)


@router.post("/orders/{id}/complete", operation_id="v3CompleteOrder",
             response_model=OrderResponse, response_model_exclude_unset=True)
def complete_order(id: str, body: CompleteInput, request: Request, db: DB, actor: Operator):
    return _transition_response(db, actor, id, "complete", body, request)


@router.post("/orders/{id}/cancel", operation_id="v3CancelOrder",
             response_model=OrderResponse, response_model_exclude_unset=True)
def cancel_order(id: str, body: CancelInput, request: Request, db: DB, actor: Authenticated):
    require(actor.role in ("user", "business"), 403, "FORBIDDEN")
    require(not body.voucherNotRedeemed or actor.role == "business", 403, "FORBIDDEN")
    reasons = STUDENT_REASONS if actor.role == "user" else KITCHEN_REASONS
    require(body.reason in reasons, 422, "INVALID_CANCEL_REASON", "Selecciona un motivo permitido para este perfil.")
    require(body.reason not in ("other", "user_other") or bool(body.notes.strip()), 422,
            "INVALID_CANCEL_REASON", "Describe el motivo de cancelación.")
    return _transition_response(db, actor, id, "cancel", body, request)
