"""Explicit V3 extension for the review payloads not supplied in the V2 source.

One business rating per completed order; one product review per purchased
product/order. Neither endpoint accepts author, academic data, or aggregates.
"""
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Request
from pydantic import BaseModel, ConfigDict, Field, StrictInt
from sqlalchemy import select
from sqlalchemy.orm import Session

from .admin import create_student_review
from .admin_models import Review
from .auth import current_user, ensure_account, require_student
from .common import iso, page_result, require
from .db import emit_event, get_db, utcnow
from .errors import ApiError
from .identity_models import User
from .operation_models import Business, Order, Product
from .review_models import ProductReview

router = APIRouter(tags=['Calificaciones V3'])
DB = Annotated[Session, Depends(get_db, scope='function')]
Student = Annotated[User, Depends(require_student)]
Authenticated = Annotated[User, Depends(current_user)]
Score = Annotated[StrictInt, Field(ge=1, le=5)]


class RatingInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    rating: Score
    comment: str = Field(default='', max_length=2000)
    foodRating: Score | None = None
    serviceRating: Score | None = None


class ProductReviewInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    productId: str = Field(min_length=1, max_length=1500)
    rating: Score
    comment: str = Field(default='', max_length=2000)


class ProductReviewsInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    reviews: list[ProductReviewInput] = Field(min_length=1, max_length=50)


class BusinessRatingResponse(BaseModel):
    id: str
    orderId: str
    businessId: str
    rating: int
    comment: str
    foodRating: int | None
    serviceRating: int | None
    createdAt: datetime
    updatedAt: datetime


class ProductReviewResponse(BaseModel):
    id: str
    productId: str
    rating: int
    comment: str
    createdAt: datetime
    updatedAt: datetime


class ProductReviewsResponse(BaseModel):
    data: list[ProductReviewResponse]


class Pagination(BaseModel):
    page: int
    limit: int
    total: int
    totalPages: int


class ReviewPage(ProductReviewsResponse):
    pagination: Pagination


def product_review_dto(row):
    # Public feedback does not expose student identity or an order's identifier.
    return {'id': row.id, 'productId': row.product_id, 'rating': row.rating,
            'comment': row.comment, 'createdAt': iso(row.created_at), 'updatedAt': iso(row.updated_at)}


def business_rating_dto(row):
    # Only returned to the student who owns the order.
    return {'id': row.id, 'orderId': row.order_id, 'businessId': row.business_id,
            'rating': row.rating, 'comment': row.comment, 'foodRating': row.food_rating,
            'serviceRating': row.service_rating, 'createdAt': iso(row.created_at),
            'updatedAt': iso(row.updated_at)}


def _completed_order(request, db, user, order_id):
    user = db.scalar(select(User).where(User.id == user.id).with_for_update()
                     .execution_options(populate_existing=True))
    user = current_user(request, db)
    require(user.role == 'user', 403, 'FORBIDDEN')
    order = db.scalar(select(Order).where(Order.id == order_id, Order.student_id == user.id)
                      .with_for_update().execution_options(populate_existing=True))
    current_user(request, db)
    require(order is not None, 404, 'ORDER_NOT_FOUND')
    require(order.status == 'completed', 409, 'ORDER_NOT_COMPLETED',
            'Solo puedes evaluar pedidos entregados.')
    return order


def _touch_catalog(db, business):
    business.version += 1
    business.updated_at = utcnow()
    emit_event(db, f'business:{business.id}', 'business.updated',
               {'id': business.id, 'version': business.version, 'updatedAt': iso(business.updated_at)})


@router.post('/orders/{id}/rating', status_code=201, response_model=BusinessRatingResponse,
             operation_id='v3CreateBusinessRating')
def rate_business(id: str, body: RatingInput, request: Request, db: DB, user: Student):
    order = _completed_order(request, db, user, id)
    # Reuse the established academic attribution and uniqueness rules.
    create_student_review(id, body.model_dump(exclude_none=True), user, db)
    row = db.scalar(select(Review).where(Review.order_id == id))
    business = db.scalar(select(Business).where(Business.id == order.business_id).with_for_update())
    current_user(request, db)
    _touch_catalog(db, business)
    order.version += 1
    order.updated_at = utcnow()
    emit_event(db, f'user:{user.id}:orders', 'order.updated',
               {'id': order.id, 'businessId': order.business_id, 'version': order.version,
                'updatedAt': iso(order.updated_at), 'isRated': True, 'change': 'rating'})
    return business_rating_dto(row)


@router.post('/orders/{id}/reviews', status_code=201, response_model=ProductReviewsResponse,
             operation_id='v3CreateProductReviews')
def review_products(id: str, body: ProductReviewsInput, request: Request, db: DB, user: Student):
    order = _completed_order(request, db, user, id)
    ids = [item.productId for item in body.reviews]
    require(len(ids) == len(set(ids)), 422, 'DUPLICATE_PRODUCT', 'No repitas un producto en la misma reseña.')
    purchased = {item.product_id for item in order.items}
    require(set(ids) <= purchased, 422, 'PRODUCT_NOT_PURCHASED', 'Solo puedes evaluar productos de este pedido.')
    if db.scalar(select(ProductReview.id).where(ProductReview.order_id == id,
                                               ProductReview.product_id.in_(ids)).limit(1)):
        raise ApiError(409, 'REVIEW_EXISTS', 'Un producto del pedido ya tiene una reseña.')
    # Same business then sorted product lock order as catalog/ordering writes.
    business = db.scalar(select(Business).where(Business.id == order.business_id).with_for_update())
    products = {p.id: p for p in db.scalars(select(Product).where(Product.id.in_(ids))
                                           .order_by(Product.id).with_for_update()
                                           .execution_options(populate_existing=True))}
    current_user(request, db)
    rows = []
    for item in body.reviews:
        row = ProductReview(order_id=id, product_id=item.productId, user_id=user.id,
                            rating=item.rating, comment=item.comment.strip())
        db.add(row)
        rows.append(row)
        product = products[item.productId]
        product.version += 1
        product.updated_at = utcnow()
        emit_event(db, f'business:{business.id}:products', 'product.updated',
                   {'id': product.id, 'businessId': business.id, 'version': product.version,
                    'updatedAt': iso(product.updated_at)})
    db.flush()
    return {'data': [product_review_dto(row) for row in rows]}


@router.get('/products/{id}/reviews', response_model=ReviewPage, operation_id='v3ListProductReviews')
def list_product_reviews(id: str, db: DB, user: Authenticated, page: int = Query(1, ge=1),
                         limit: int = Query(20, ge=1, le=100)):
    product = db.get(Product, id)
    require(product is not None and not product.is_deleted, 404, 'PRODUCT_NOT_FOUND')
    business = db.get(Business, product.business_id)
    require(business is not None and business.is_active, 404, 'BUSINESS_NOT_FOUND')
    require(user.role != 'business' or user.business_id == business.id, 403, 'FORBIDDEN')
    return page_result(db, select(ProductReview).where(ProductReview.product_id == id)
                       .order_by(ProductReview.created_at.desc(), ProductReview.id), product_review_dto, page, limit)
