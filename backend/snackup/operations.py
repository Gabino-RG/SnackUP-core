"""Transactional catalog, kitchen and student ordering HTTP API."""
from __future__ import annotations

import hashlib
import hmac
import io
import json
import re
import secrets
import warnings
from datetime import date as Date, datetime, time, timedelta, timezone
from decimal import Decimal
from pathlib import Path
from typing import Annotated, Literal
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Body, Depends, File, Form, Header, Query, Request, Response, UploadFile
from PIL import Image, UnidentifiedImageError
from pydantic import BaseModel, ConfigDict, Field, StrictInt
from sqlalchemy import and_, case, func, or_, select
from sqlalchemy.orm import Session

from .auth import ensure_account, require_business, require_student
from .common import iso, page_result, require, validate_body, version_check
from .db import emit_event, get_db, new_id, utcnow
from .errors import ApiError
from .identity_models import User
from .operation_models import Business, IdempotencyRecord, MediaFile, Order, OrderItem, OrderTransition, Product

router = APIRouter()
ACTIVE = ("pending", "accepted", "preparing", "ready")
DB = Annotated[Session, Depends(get_db, scope="function")]
Operator = Annotated[User, Depends(require_business)]
Student = Annotated[User, Depends(require_student)]
PAGE = Annotated[int, Query(ge=1)]
LIMIT = Annotated[int, Query(ge=1, le=200)]


def business_dict(b: Business) -> dict:
    return {"id": b.id, "name": b.name, "category": b.category, "description": b.description,
            "timezone": b.timezone, "cafeteriaId": b.cafeteria_id, "cafeteriaName": b.cafeteria_name,
            "isActive": b.is_active, "isOpen": b.is_open, "version": b.version}


def product_dict(p: Product) -> dict:
    return {"id": p.id, "businessId": p.business_id, "name": p.name, "description": p.description,
            "category": p.category, "price": float(p.price), "stock": p.stock, "imageUrl": p.image_url,
            "isAvailable": p.is_available, "isFeatured": p.is_featured, "version": p.version,
            "updatedAt": iso(p.updated_at)}


def order_dict(o: Order, db: Session, include_pickup: bool = False) -> dict:
    """Default DTO never reveals the code, student ID, email or academic ID."""
    result = {"id": o.id, "businessId": o.business_id, "orderNumber": o.order_number,
              "version": o.version, "status": o.status, "customerName": o.customer_name,
              "paymentMethod": o.payment_method, "paymentStatus": o.payment_status,
              "total": float(o.total), "subtotal": float(o.total),
              "items": [{"id": x.id, "productId": x.product_id, "name": x.name,
                         "quantity": x.quantity, "price": float(x.price), "notes": x.notes} for x in o.items],
              "cancelReason": o.cancel_reason, "cancelNotes": o.cancel_notes}
    for key, attr in (("createdAt", "created_at"), ("updatedAt", "updated_at"),
                      ("acceptedAt", "accepted_at"), ("preparingAt", "preparing_at"),
                      ("readyAt", "ready_at"), ("completedAt", "completed_at"),
                      ("cancelledAt", "cancelled_at"), ("scheduledPickupTime", "scheduled_pickup_time")):
        value = getattr(o, attr)
        result[key] = iso(value) if value else None
    if include_pickup:
        result["pickupCode"] = o.pickup_code
    return result


def _business(db: Session, user: User, business_id: str, lock: bool = False) -> Business:
    require(user.business_id == business_id, 403, "FORBIDDEN", "El local no pertenece a esta cuenta.")
    stmt = select(Business).where(Business.id == business_id)
    if lock:
        stmt = stmt.with_for_update().execution_options(populate_existing=True)
    b = db.scalar(stmt)
    require(b is not None, 404, "NOT_FOUND", "Local no encontrado.")
    require(b.is_active, 403, "BUSINESS_INACTIVE", "El local está desactivado.")
    return b


def _product(db: Session, user: User, product_id: str, lock: bool = False) -> Product:
    stmt = select(Product).where(Product.id == product_id, Product.business_id == user.business_id,
                                 Product.is_deleted.is_(False))
    if lock:
        stmt = stmt.with_for_update().execution_options(populate_existing=True)
    product = db.scalar(stmt)
    require(product is not None, 404, "NOT_FOUND", "Producto no encontrado.")
    _business(db, user, product.business_id)
    return product


def _touch(record) -> None:
    record.version += 1
    record.updated_at = utcnow()


def _product_fields(db: Session, b: Business, data: dict, request: Request, current: Product | None = None) -> dict:
    price = Decimal(str(data["price"]))
    require(price.is_finite() and price == price.quantize(Decimal("0.01")),
            422, "INVALID_PRICE", "El precio admite como máximo dos decimales.")
    stock = data.get("stock", current.stock if current else None)
    require(stock != 0 or data["isAvailable"] is False, 422, "INVALID_STOCK",
            "Un producto sin existencias debe estar no disponible.")
    image_url = data["imageUrl"]
    if image_url is not None:
        # Only attach media actually uploaded by this business; no arbitrary remote URLs.
        origin = str(request.app.state.settings.public_origin).rstrip("/")
        prefix = origin + "/media/"
        filename = image_url[len(prefix):] if image_url.startswith(prefix) else ""
        media = db.scalar(select(MediaFile).where(MediaFile.filename == filename,
                                                  MediaFile.business_id == b.id))
        require(media is not None, 422, "INVALID_IMAGE", "Sube una imagen de este local antes de asociarla.")
    # Preserve space for returns of already reserved stock, including after edits.
    if current and stock is not None:
        reserved = db.scalar(select(func.coalesce(func.sum(OrderItem.reserved_quantity), 0))
                             .join(Order, Order.id == OrderItem.order_id)
                             .where(OrderItem.product_id == current.id, Order.status.in_(ACTIVE),
                                    Order.stock_restored.is_(False)))
        require(stock + reserved <= 1_000_000, 422, "INVALID_STOCK",
                "El inventario y las reservas pendientes exceden el máximo permitido.")
    fields = {"name": data["name"].strip(), "description": data["description"].strip(),
              "category": data["category"].strip(), "price": price, "image_url": image_url,
              "is_available": data["isAvailable"], "is_featured": data["isFeatured"]}
    require(bool(fields["name"] and fields["category"]), 422, "VALIDATION_ERROR", "Nombre y categoría son obligatorios.")
    if "stock" in data:
        fields["stock"] = stock
    return fields


@router.get("/businesses/{id}")
def get_business(id: str, db: DB, user: Operator):
    return business_dict(_business(db, user, id))


@router.patch("/businesses/{id}")
def update_business(id: str, db: DB, user: Operator, body: dict = Body(...)):
    validate_body("updateBusiness", body)
    b = _business(db, user, id, True)
    version_check(b, body["expectedVersion"])
    require(bool(body["name"].strip()), 422, "VALIDATION_ERROR", "El nombre es obligatorio.")
    for field in ("name", "category", "description"):
        setattr(b, field, body[field].strip())
    _touch(b)
    emit_event(db, f"business:{b.id}", "business.updated", {"id": b.id, "version": b.version})
    return business_dict(b)


@router.patch("/businesses/{id}/status")
def set_business_open(id: str, db: DB, user: Operator, body: dict = Body(...)):
    validate_body("setBusinessOpen", body)
    b = _business(db, user, id, True)
    version_check(b, body["expectedVersion"])
    b.is_open = body["isOpen"]
    _touch(b)
    emit_event(db, f"business:{b.id}", "business.updated", {"id": b.id, "version": b.version})
    return business_dict(b)


@router.get("/businesses/{id}/products")
def list_products(id: str, db: DB, user: Operator, page: PAGE = 1,
                  limit: Annotated[int, Query(ge=1, le=100)] = 20, q: str = "",
                  isAvailable: bool | None = None):
    _business(db, user, id)
    stmt = select(Product).where(Product.business_id == id, Product.is_deleted.is_(False))
    if q:
        stmt = stmt.where(Product.name.ilike(f"%{q.strip()}%"))
    if isAvailable is not None:
        stmt = stmt.where(Product.is_available == isAvailable)
    return page_result(db, stmt.order_by(Product.created_at, Product.id), product_dict, page, limit)


@router.get("/products/{id}")
def get_product(id: str, db: DB, user: Operator):
    return product_dict(_product(db, user, id))


@router.post("/businesses/{id}/products", status_code=201)
def create_product(id: str, request: Request, db: DB, user: Operator, body: dict = Body(...)):
    validate_body("createProduct", body)
    b = _business(db, user, id)
    p = Product(business_id=b.id, **_product_fields(db, b, body, request))
    db.add(p)
    db.flush()
    return product_dict(p)


@router.patch("/products/{id}")
def update_product(id: str, request: Request, db: DB, user: Operator, body: dict = Body(...)):
    validate_body("updateProduct", body)
    p = _product(db, user, id, True)
    version_check(p, body["expectedVersion"])
    b = _business(db, user, p.business_id)
    for field, value in _product_fields(db, b, body, request, p).items():
        setattr(p, field, value)
    _touch(p)
    return product_dict(p)


@router.delete("/products/{id}", status_code=204)
def delete_product(id: str, db: DB, user: Operator, body: dict = Body(...)):
    validate_body("deleteProduct", body)
    p = _product(db, user, id, True)
    version_check(p, body["expectedVersion"])
    p.is_deleted, p.is_available = True, False
    _touch(p)
    return Response(status_code=204)


@router.post("/media", status_code=201)
def upload_product_image(request: Request, db: DB, user: Operator,
                         purpose: str = Form(...), file: UploadFile = File(...)):
    b = _business(db, user, user.business_id)
    require(purpose == "product", 422, "INVALID_MEDIA_PURPOSE", "El destino de la imagen debe ser product.")
    content = file.file.read(5 * 1024 * 1024 + 1)
    require(0 < len(content) <= 5 * 1024 * 1024, 413 if content else 422,
            "FILE_TOO_LARGE" if content else "INVALID_IMAGE", "La imagen debe contener entre 1 byte y 5 MiB.")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(content)) as source:
                require(source.format in ("JPEG", "PNG", "WEBP"), 422, "INVALID_IMAGE", "Usa JPEG, PNG o WebP.")
                require(source.width * source.height <= 20_000_000 and max(source.size) <= 8192,
                        422, "INVALID_IMAGE", "La imagen excede las dimensiones permitidas.")
                require(getattr(source, "n_frames", 1) == 1, 422, "INVALID_IMAGE", "Usa una imagen sin animación.")
                source.load()
                # Re-encode raster pixels; discard metadata and any appended executable payload.
                converted = source.convert("RGBA" if "A" in source.getbands() else "RGB")
                encoded = io.BytesIO()
                converted.save(encoded, format="WEBP", quality=85, method=4)
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError, Image.DecompressionBombWarning):
        raise ApiError(422, "INVALID_IMAGE", "El archivo no es una imagen válida.") from None
    data = encoded.getvalue()
    media_id = new_id()
    filename = f"{media_id}.webp"
    directory = Path(request.app.state.settings.media_dir)
    directory.mkdir(parents=True, exist_ok=True)
    # A random name cannot collide with a previously published image; never use the supplied filename.
    with (directory / filename).open("xb") as output:
        output.write(data)
    db.add(MediaFile(id=media_id, business_id=b.id, filename=filename, mime_type="image/webp", size=len(data)))
    db.flush()
    return {"id": media_id, "url": str(request.app.state.settings.public_origin).rstrip("/") + "/media/" + filename}


def _order(db: Session, user: User, id: str, student: bool = False, lock: bool = False) -> Order:
    stmt = select(Order).where(Order.id == id)
    stmt = stmt.where(Order.student_id == user.id) if student else stmt.where(Order.business_id == user.business_id)
    if lock:
        stmt = stmt.with_for_update().execution_options(populate_existing=True)
    order = db.scalar(stmt)
    require(order is not None, 404, "NOT_FOUND", "Pedido no encontrado.")
    if not student:
        _business(db, user, order.business_id)
    return order


def _order_event(db: Session, order: Order, created: bool = False) -> None:
    event = "order.created" if created else "order.updated"
    data = {"id": order.id, "version": order.version, "status": order.status}
    emit_event(db, f"business:{order.business_id}:orders", event, data)
    emit_event(db, f"user:{order.student_id}:orders", event, data)


@router.get("/businesses/{id}/orders/active")
def active_orders(id: str, db: DB, user: Operator, page: PAGE = 1, limit: LIMIT = 20):
    _business(db, user, id)
    stmt = select(Order).where(Order.business_id == id, Order.status.in_(ACTIVE)).order_by(Order.created_at, Order.id)
    return page_result(db, stmt, lambda o: order_dict(o, db), page, limit)


@router.get("/orders/{id}")
def get_order(id: str, db: DB, user: Operator):
    return order_dict(_order(db, user, id), db)


def _range(start: Date, end: Date, tz: str) -> tuple[datetime, datetime]:
    require(start <= end and (end - start).days <= 366, 422, "INVALID_DATE_RANGE",
            "El rango debe ser válido y no superar 367 días.")
    zone = ZoneInfo(tz)
    require(end < Date.max, 422, "INVALID_DATE_RANGE", "La fecha final está fuera del rango permitido.")
    return (datetime.combine(start, time.min, zone).astimezone(timezone.utc),
            datetime.combine(end + timedelta(days=1), time.min, zone).astimezone(timezone.utc))


def _history_filter(id: str, start: datetime, end: datetime):
    return and_(Order.business_id == id, or_(
        and_(Order.status == "completed", Order.completed_at >= start, Order.completed_at < end),
        and_(Order.status == "cancelled", Order.cancelled_at >= start, Order.cancelled_at < end)))


def _summary(db: Session, condition) -> dict:
    row = db.execute(select(
        func.coalesce(func.sum(case((Order.status == "completed", 1), else_=0)), 0),
        func.coalesce(func.sum(case((Order.status == "cancelled", 1), else_=0)), 0),
        func.coalesce(func.sum(case((Order.status == "completed", Order.total), else_=0)), 0)
    ).where(condition)).one()
    return {"completed": int(row[0]), "cancelled": int(row[1]), "totalSold": float(row[2])}


@router.get("/businesses/{id}/orders/history")
def order_history(id: str, date: Date, db: DB, user: Operator, page: PAGE = 1, limit: LIMIT = 20):
    b = _business(db, user, id)
    start, end = _range(date, date, b.timezone)
    condition = _history_filter(id, start, end)
    stmt = select(Order).where(condition).order_by(func.coalesce(Order.completed_at, Order.cancelled_at).desc(), Order.id)
    result = page_result(db, stmt, lambda o: order_dict(o, db), page, limit)
    result["summary"] = _summary(db, condition)
    return result


@router.get("/businesses/{id}/stats")
def sales_summary(id: str, db: DB, user: Operator,
                  from_date: Annotated[Date, Query(alias="from")], to: Date):
    b = _business(db, user, id)
    start, end = _range(from_date, to, b.timezone)
    return _summary(db, _history_filter(id, start, end))


def _restore_stock(db: Session, order: Order) -> None:
    if order.stock_restored:
        return
    quantities: dict[str, int] = {}
    for item in order.items:
        quantities[item.product_id] = quantities.get(item.product_id, 0) + item.reserved_quantity
    # Same ascending product lock order as purchases; no double-return after repeated cancellation.
    products = db.scalars(select(Product).where(Product.id.in_(sorted(quantities)))
                          .order_by(Product.id).with_for_update().execution_options(populate_existing=True)).all()
    for p in products:
        returned = quantities[p.id]
        if returned and p.stock is not None:
            was_empty = p.stock == 0
            p.stock += returned
            if was_empty and not p.is_deleted:
                p.is_available = True
            _touch(p)
    order.stock_restored = True


def transition(db: Session, user: User, id: str, action: str, body: dict, request: Request, student: bool = False) -> dict:
    operation_ids = {"accept": "acceptOrder", "start": "startOrder", "ready": "readyOrder",
                     "complete": "completeOrder", "cancel": "cancelOrder"}
    validate_body("acceptOrder" if student else operation_ids[action], body)
    order = _order(db, user, id, student=student, lock=True)
    version_check(order, body["expectedVersion"])
    allowed = {"accept": ("pending",), "start": ("accepted",), "ready": ("preparing",),
               "complete": ("ready",), "cancel": ("pending",) if student else ("pending", "accepted", "preparing")}
    require(order.status in allowed[action], 409, "INVALID_STATUS_TRANSITION", "La acción no corresponde al estado actual.")
    new_status = {"accept": "accepted", "start": "preparing", "ready": "ready", "complete": "completed", "cancel": "cancelled"}[action]
    if action == "complete":
        request.app.state.limiter.check("pickup", user.id + ":" + order.id, 10, 60)
        require(hmac.compare_digest(body["code"].strip().encode("utf-8"), order.pickup_code.encode("utf-8")), 422, "VERIFICATION_FAILED",
                "El código del pedido es incorrecto.")
        order.verification_method, order.verified_by = body["method"], user.id
    if action == "cancel":
        if not student:
            require(body["reason"] != "other" or bool(body.get("notes", "").strip()), 422,
                    "INVALID_CANCEL_REASON", "Describe el motivo de cancelación.")
        order.cancel_reason = "student_cancelled" if student else body["reason"]
        order.cancel_notes = None if student else body.get("notes", "").strip() or None
        order.cancelled_by = user.id
        _restore_stock(db, order)
    previous = order.status
    order.status = new_status
    _touch(order)
    setattr(order, new_status + "_at", order.updated_at)
    db.add(OrderTransition(order_id=order.id, actor_id=user.id, from_status=previous,
                           to_status=new_status, version=order.version))
    _order_event(db, order)
    db.flush()
    return order_dict(order, db, include_pickup=student)


@router.post("/orders/{id}/accept")
def accept_order(id: str, request: Request, db: DB, user: Operator, body: dict = Body(...)):
    return transition(db, user, id, "accept", body, request)


@router.post("/orders/{id}/start")
def start_order(id: str, request: Request, db: DB, user: Operator, body: dict = Body(...)):
    return transition(db, user, id, "start", body, request)


@router.post("/orders/{id}/ready")
def ready_order(id: str, request: Request, db: DB, user: Operator, body: dict = Body(...)):
    return transition(db, user, id, "ready", body, request)


@router.post("/orders/{id}/complete")
def complete_order(id: str, request: Request, db: DB, user: Operator, body: dict = Body(...)):
    return transition(db, user, id, "complete", body, request)


@router.post("/orders/{id}/cancel")
def cancel_order(id: str, request: Request, db: DB, user: Operator, body: dict = Body(...)):
    return transition(db, user, id, "cancel", body, request)


class StudentItemInput(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    productId: str = Field(min_length=1, max_length=36)
    quantity: StrictInt = Field(ge=1, le=99)
    notes: str = Field(default="", max_length=500)


class StudentOrderInput(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    businessId: str = Field(min_length=1, max_length=36)
    items: list[StudentItemInput] = Field(min_length=1, max_length=50)
    paymentMethod: Literal["cash"] = "cash"


@router.get("/student/businesses")
def student_businesses(db: DB, user: Student, page: PAGE = 1, limit: LIMIT = 20):
    return page_result(db, select(Business).where(Business.is_active.is_(True)).order_by(Business.name, Business.id),
                       business_dict, page, limit)


@router.get("/student/businesses/{id}/products")
def student_products(id: str, db: DB, user: Student, page: PAGE = 1,
                     limit: Annotated[int, Query(ge=1, le=100)] = 20):
    b = db.get(Business, id)
    require(b is not None and b.is_active, 404, "NOT_FOUND", "Local no encontrado.")
    stmt = select(Product).where(Product.business_id == id, Product.is_deleted.is_(False),
                                 Product.is_available.is_(True)).order_by(Product.category, Product.name, Product.id)
    return page_result(db, stmt, product_dict, page, limit)


@router.post("/student/orders", status_code=201)
def create_student_order(body: StudentOrderInput, request: Request, db: DB, user: Student,
                         idempotency_key: Annotated[str, Header(alias="Idempotency-Key", min_length=16, max_length=128)]):
    require(bool(re.fullmatch(r"[A-Za-z0-9._:-]{16,128}", idempotency_key)), 422,
            "INVALID_IDEMPOTENCY_KEY", "Utiliza una clave única de entre 16 y 128 caracteres ASCII.")
    request.app.state.limiter.check("order-create", user.id, 30, 60)
    payload_hash = hashlib.sha256(json.dumps(body.model_dump(), sort_keys=True, ensure_ascii=False,
                                            separators=(",", ":")).encode()).hexdigest()
    # Serializes retries by the same user even when the idempotency row does not yet exist.
    # PostgreSQL READ COMMITTED sees the first committed result after waiting on this lock.
    db.scalar(select(User).where(User.id == user.id).with_for_update().execution_options(populate_existing=True))
    require(user.is_active and user.role == "user" and user.email_verified and user.approval_status == "approved",
            403, "FORBIDDEN", "La cuenta no está autorizada para comprar.")
    ensure_account(user, db)
    previous = db.scalar(select(IdempotencyRecord).where(IdempotencyRecord.user_id == user.id,
                                                         IdempotencyRecord.key == idempotency_key))
    if previous:
        require(hmac.compare_digest(previous.payload_hash, payload_hash), 409, "IDEMPOTENCY_CONFLICT",
                "La clave ya se utilizó con otro pedido.")
        return previous.response_json
    require(len({item.productId for item in body.items}) == len(body.items), 422, "DUPLICATE_PRODUCT",
            "Agrupa las cantidades de cada producto en un solo renglón.")
    b = db.scalar(select(Business).where(Business.id == body.businessId).with_for_update()
                  .execution_options(populate_existing=True))
    require(b is not None and b.is_active, 404, "NOT_FOUND", "Local no encontrado.")
    require(b.is_open, 409, "BUSINESS_CLOSED", "El local no está recibiendo pedidos.")
    product_ids = sorted(item.productId for item in body.items)
    products = db.scalars(select(Product).where(Product.id.in_(product_ids), Product.business_id == b.id)
                          .order_by(Product.id).with_for_update().execution_options(populate_existing=True)).all()
    by_id = {p.id: p for p in products}
    for item in body.items:
        p = by_id.get(item.productId)
        require(p is not None and not p.is_deleted, 422, "INVALID_PRODUCT", "Uno de los productos no pertenece al local.")
        require(p.is_available, 409, "PRODUCT_UNAVAILABLE", "Uno de los productos no está disponible.")
        require(p.stock is None or p.stock >= item.quantity, 409, "INSUFFICIENT_STOCK", "No hay existencias suficientes.")
    now = utcnow()
    order = Order(id=new_id(), business_id=b.id, student_id=user.id, order_number=b.next_order_number,
                  customer_name=user.display_name, total=Decimal("0.00"),
                  pickup_code=f"{secrets.randbelow(100_000_000):08d}", created_at=now, updated_at=now,
                  version=1, status="pending", payment_method="cash", payment_status="pay_at_pickup", stock_restored=False)
    b.next_order_number += 1
    db.add(order)
    for item in body.items:
        p = by_id[item.productId]
        reserved = item.quantity if p.stock is not None else 0
        order.items.append(OrderItem(product_id=p.id, name=p.name, quantity=item.quantity, price=p.price,
                                      notes=item.notes.strip(), reserved_quantity=reserved))
        order.total += p.price * item.quantity
        if reserved:
            p.stock -= reserved
            if p.stock == 0:
                p.is_available = False
            _touch(p)
    db.flush()
    result = order_dict(order, db, include_pickup=True)
    db.add(IdempotencyRecord(user_id=user.id, key=idempotency_key, payload_hash=payload_hash,
                             order_id=order.id, response_json=result))
    db.add(OrderTransition(order_id=order.id, actor_id=user.id, from_status=None, to_status="pending", version=1))
    _order_event(db, order, created=True)
    db.flush()
    return result


@router.get("/student/orders")
def student_orders(db: DB, user: Student, page: PAGE = 1, limit: LIMIT = 20):
    stmt = select(Order).where(Order.student_id == user.id).order_by(Order.created_at.desc(), Order.id)
    return page_result(db, stmt, lambda o: order_dict(o, db, include_pickup=True), page, limit)


@router.get("/student/orders/{id}")
def get_student_order(id: str, db: DB, user: Student):
    return order_dict(_order(db, user, id, student=True), db, include_pickup=True)


@router.post("/student/orders/{id}/cancel")
def cancel_student_order(id: str, request: Request, db: DB, user: Student, body: dict = Body(...)):
    return transition(db, user, id, "cancel", body, request, student=True)
