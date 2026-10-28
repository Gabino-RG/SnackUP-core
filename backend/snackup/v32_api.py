"""Additive shopping, scheduling and history routes for the existing V3 API."""
from datetime import date, datetime
from typing import Literal
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Body, Query, Request, Response
from pydantic import AwareDatetime, Field, StrictBool, StrictInt, field_validator
from sqlalchemy import func, select

from .auth import as_utc, current_user, require_student
from .common import iso, require
from .db import emit_event, utcnow
from .identity_models import User
from .operation_models import Business, Order, Product
from .operations import _order, _touch, check_optional_version
from .v3_operations import (Authenticated, BusinessResponse, DB, Limit, Operator, OrderPageResponse,
    Page, PaginationResponse, ProductPageResponse, ProductResponse, ResponseModel,
    StrictInput, Student, VersionInput, _business_for_write, _orders_page, _page_rows,
    _product_aggregates, business_dto, product_dto)
from .v32_models import CartItem, Favorite, MealVoucherUse
from .v32_services import closing_at, release_voucher

router = APIRouter(tags=['Extensiones V3.2'])


class ClosingInput(VersionInput):
    autoCloseEnabled: StrictBool
    closeTimeLocal: str | None = Field(default=None, pattern=r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$')


class PostponeInput(VersionInput):
    until: AwareDatetime = Field(strict=False)

    @field_validator('until', mode='before')
    @classmethod
    def iso_time(cls, value):
        if not isinstance(value, str):
            raise ValueError('Envía una fecha ISO 8601 con zona horaria.')
        return value


def _business_changed(db, business):
    _touch(business)
    emit_event(db, f'business:{business.id}', 'business.updated', {
        'id': business.id, 'version': business.version, 'updatedAt': iso(business.updated_at),
    })
    return business_dto(business, db)


@router.patch('/businesses/{id}/closing-schedule', response_model=BusinessResponse, operation_id='v32ClosingSchedule')
def closing_schedule(id: str, body: ClosingInput, request: Request, db: DB, actor: Operator):
    business = _business_for_write(db, request, actor, id)
    check_optional_version(business, body.model_dump(exclude_unset=True))
    close_time = body.closeTimeLocal if 'closeTimeLocal' in body.model_fields_set else business.close_time_local
    require(not body.autoCloseEnabled or close_time is not None, 422, 'CLOSING_TIME_REQUIRED')
    business.auto_close_enabled, business.close_time_local = body.autoCloseEnabled, close_time
    business.postponed_close_at = None
    # A previously processed day stays processed; changing a time never reopens.
    return _business_changed(db, business)


@router.post('/businesses/{id}/postpone-closing', response_model=BusinessResponse, operation_id='v32PostponeClosing')
def postpone_closing(id: str, body: PostponeInput, request: Request, db: DB, actor: Operator):
    business = _business_for_write(db, request, actor, id)
    check_optional_version(business, body.model_dump(exclude_unset=True))
    now, until = utcnow(), as_utc(body.until)
    zone = ZoneInfo(business.timezone)
    day = now.astimezone(zone).date()
    deadline = closing_at(business, day)
    require(business.auto_close_enabled and deadline is not None, 422, 'CLOSING_NOT_CONFIGURED')
    require(business.last_auto_close_date != day, 409, 'CLOSING_ALREADY_PROCESSED',
            'El cierre de hoy ya se procesó. La reapertura es manual.')
    require(until > now and until > deadline and until.astimezone(zone).date() == day,
            422, 'INVALID_POSTPONEMENT', 'Pospón a una hora futura de hoy, posterior al cierre vigente.')
    business.postponed_close_at = until
    return _business_changed(db, business)


def _available_products(actor):
    statement = select(Product).join(Business, Business.id == Product.business_id).where(
        Business.is_active.is_(True), Product.is_deleted.is_(False), Product.is_available.is_(True))
    if actor.role == 'business':
        statement = statement.where(Business.id == actor.business_id)
    return statement


def _products_page(db, statement, page, limit):
    rows, pagination = _page_rows(db, statement, page, limit)
    aggregates = _product_aggregates(db, [row.id for row in rows])
    return {'data': [product_dto(row, db, aggregates=aggregates) for row in rows], 'pagination': pagination}


@router.get('/products/search', response_model=ProductPageResponse, operation_id='v32SearchProducts')
def search_products(db: DB, actor: Authenticated, q: str = Query(min_length=1, max_length=160),
                    page: Page = 1, limit: Limit = 20):
    require(bool(q.strip()), 422, 'INVALID_SEARCH')
    search = q.strip().replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_')
    statement = _available_products(actor).where(Product.name.ilike(f'%{search}%', escape='\\'))
    return _products_page(db, statement.order_by(Product.name, Product.id), page, limit)


@router.get('/products/featured', response_model=ProductPageResponse, operation_id='v32FeaturedProducts')
def featured_products(db: DB, actor: Authenticated, page: Page = 1, limit: Limit = 5):
    return _products_page(db, _available_products(actor).where(Product.is_featured.is_(True))
                          .order_by(Product.updated_at.desc(), Product.id), page, limit)


@router.get('/users/me/orders/history', response_model=OrderPageResponse, response_model_exclude_unset=True,
            operation_id='v32MyOrderHistory')
def my_history(db: DB, actor: Student, page: Page = 1, limit: Limit = 20,
               status: Literal['completed', 'cancelled'] | None = None):
    statement = select(Order).where(Order.student_id == actor.id,
        Order.status == status if status else Order.status.in_(('completed', 'cancelled')))
    return _orders_page(db, statement.order_by(func.coalesce(Order.completed_at, Order.cancelled_at).desc(), Order.id),
                        actor, page, limit)


class CartInput(StrictInput):
    productId: str = Field(min_length=1, max_length=1500)
    quantity: StrictInt = Field(ge=1, le=99)
    notes: str = Field(default='', max_length=500)


class CartPatch(StrictInput):
    quantity: StrictInt | None = Field(default=None, ge=1, le=99)
    notes: str | None = Field(default=None, max_length=500)


class FavoriteInput(StrictInput):
    notes: str = Field(default='', max_length=500)


class SavedProductResponse(ResponseModel):
    id: str
    productId: str
    product: ProductResponse | None
    available: bool
    notes: str
    createdAt: datetime
    updatedAt: datetime


class CartResponse(SavedProductResponse):
    quantity: int


class CartPage(ResponseModel):
    data: list[CartResponse]
    pagination: PaginationResponse


class FavoritePage(ResponseModel):
    data: list[SavedProductResponse]
    pagination: PaginationResponse


def lock_student(db, request, actor):
    db.scalar(select(User).where(User.id == actor.id).with_for_update(key_share=True).execution_options(populate_existing=True))
    return require_student(current_user(request, db))


def _saved_product(db, product_id):
    product = db.get(Product, product_id)
    require(product is not None and not product.is_deleted, 404, 'PRODUCT_NOT_FOUND')
    business = db.get(Business, product.business_id)
    require(business is not None and business.is_active, 404, 'BUSINESS_NOT_FOUND')
    return product


def _saved_dto(row, db):
    product = db.get(Product, row.product_id)
    business = db.get(Business, product.business_id) if product else None
    visible = product is not None and not product.is_deleted and business is not None and business.is_active
    result = {'id': row.id, 'productId': row.product_id, 'product': product_dto(product, db) if visible else None,
              'available': bool(visible and product.is_available and business.is_open), 'notes': row.notes,
              'createdAt': iso(row.created_at), 'updatedAt': iso(row.updated_at)}
    if isinstance(row, CartItem):
        result['quantity'] = row.quantity
    return result


def _saved_page(db, actor, model, page, limit):
    rows, pagination = _page_rows(db, select(model).where(model.user_id == actor.id)
                                  .order_by(model.created_at, model.id), page, limit)
    return {'data': [_saved_dto(row, db) for row in rows], 'pagination': pagination}


@router.get('/users/me/cart/items', response_model=CartPage, operation_id='v32ListCart')
def list_cart(db: DB, actor: Student, page: Page = 1, limit: Limit = 50):
    return _saved_page(db, actor, CartItem, page, limit)


@router.post('/users/me/cart/items', response_model=CartResponse, operation_id='v32UpsertCartItem')
def upsert_cart(body: CartInput, request: Request, db: DB, actor: Student):
    actor = lock_student(db, request, actor)
    _saved_product(db, body.productId)
    row = db.scalar(select(CartItem).where(CartItem.user_id == actor.id, CartItem.product_id == body.productId))
    if row is None:
        require(db.scalar(select(func.count()).select_from(CartItem).where(CartItem.user_id == actor.id)) < 100,
                422, 'CART_LIMIT_REACHED')
        row = CartItem(user_id=actor.id, product_id=body.productId)
        db.add(row)
    row.quantity, row.notes, row.updated_at = body.quantity, body.notes.strip(), utcnow()
    db.flush()
    return _saved_dto(row, db)


@router.patch('/users/me/cart/items/{id}', response_model=CartResponse, operation_id='v32UpdateCartItem')
def patch_cart(id: str, body: CartPatch, request: Request, db: DB, actor: Student):
    actor = lock_student(db, request, actor)
    row = db.scalar(select(CartItem).where(CartItem.id == id, CartItem.user_id == actor.id))
    require(row is not None, 404, 'CART_ITEM_NOT_FOUND')
    changes = body.model_dump(exclude_unset=True)
    require(bool(changes) and all(value is not None for value in changes.values()), 422, 'INVALID_INPUT')
    for key, value in changes.items():
        setattr(row, key, value.strip() if key == 'notes' else value)
    row.updated_at = utcnow()
    return _saved_dto(row, db)


@router.delete('/users/me/cart/items/{id}', status_code=204, operation_id='v32DeleteCartItem')
def delete_cart(id: str, request: Request, db: DB, actor: Student):
    actor = lock_student(db, request, actor)
    row = db.scalar(select(CartItem).where(CartItem.id == id, CartItem.user_id == actor.id))
    require(row is not None, 404, 'CART_ITEM_NOT_FOUND')
    db.delete(row)
    return Response(status_code=204)


@router.get('/users/me/favorites', response_model=FavoritePage, operation_id='v32ListFavorites')
def list_favorites(db: DB, actor: Student, page: Page = 1, limit: Limit = 20):
    return _saved_page(db, actor, Favorite, page, limit)


@router.put('/users/me/favorites/{productId}', response_model=SavedProductResponse, operation_id='v32SaveFavorite')
def save_favorite(productId: str, request: Request, db: DB, actor: Student,
                   body: FavoriteInput = Body(default_factory=FavoriteInput)):
    actor = lock_student(db, request, actor)
    _saved_product(db, productId)
    row = db.scalar(select(Favorite).where(Favorite.user_id == actor.id, Favorite.product_id == productId))
    if row is None:
        require(db.scalar(select(func.count()).select_from(Favorite).where(Favorite.user_id == actor.id)) < 500,
                422, 'FAVORITES_LIMIT_REACHED')
        row = Favorite(user_id=actor.id, product_id=productId, notes=body.notes.strip())
        db.add(row)
    elif 'notes' in body.model_fields_set:
        row.notes = body.notes.strip()
    row.updated_at = utcnow()
    db.flush()
    return _saved_dto(row, db)


@router.delete('/users/me/favorites/{productId}', status_code=204, operation_id='v32DeleteFavorite')
def delete_favorite(productId: str, request: Request, db: DB, actor: Student):
    actor = lock_student(db, request, actor)
    row = db.scalar(select(Favorite).where(Favorite.user_id == actor.id, Favorite.product_id == productId))
    if row:
        db.delete(row)
    return Response(status_code=204)


class VoucherReleaseInput(VersionInput):
    notRedeemed: StrictBool


class VoucherResponse(ResponseModel):
    orderId: str
    state: str
    localDate: date


@router.post('/orders/{id}/meal-voucher/release', response_model=VoucherResponse, operation_id='v32ReleaseMealVoucher')
def confirm_voucher_not_redeemed(id: str, body: VoucherReleaseInput, request: Request, db: DB, actor: Operator):
    require(body.notRedeemed, 422, 'CONFIRMATION_REQUIRED', 'Confirma que el vale no fue redimido.')
    db.scalar(select(User).where(User.id == actor.id).with_for_update(key_share=True).execution_options(populate_existing=True))
    actor = current_user(request, db)
    order = _order(db, actor, id, lock=True)
    current_user(request, db)
    check_optional_version(order, body.model_dump(exclude_unset=True))
    release_voucher(db, order, actor)
    voucher = db.scalar(select(MealVoucherUse).where(MealVoucherUse.order_id == id))
    return {'orderId': id, 'state': voucher.state, 'localDate': voucher.local_date}
