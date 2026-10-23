"""Shared V3.2 rules, including legacy writes to the same rows."""
from datetime import datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import func, select

from .auth import as_utc
from .common import iso, require
from .db import emit_event, utcnow
from .identity_models import audit_event
from .operation_models import Business, Order, Product
from .v32_models import MealVoucherUse

CAMPUS_ZONE = ZoneInfo('America/Mexico_City')


def closing_at(business, local_date):
    if not business.auto_close_enabled or not business.close_time_local:
        return None
    zone = ZoneInfo(business.timezone)
    regular = datetime.combine(local_date, time.fromisoformat(business.close_time_local), zone)
    postponed = business.postponed_close_at
    if postponed and as_utc(postponed).astimezone(zone).date() == local_date:
        return max(regular.astimezone(timezone.utc), as_utc(postponed))
    return regular.astimezone(timezone.utc)


def notify_business_closed(db, business):
    # No student identity, pickup code or chat contents in the outbox.
    for order in db.scalars(select(Order).where(Order.business_id == business.id,
            Order.status.in_(('pending', 'accepted', 'preparing', 'ready')),
            Order.scheduled_pickup_time.is_not(None))):
        emit_event(db, f'user:{order.student_id}:orders', 'order.business_closed', {
            'id': order.id, 'businessId': business.id, 'version': order.version,
            'updatedAt': iso(order.updated_at), 'status': order.status,
        })


def close_if_due(db, business, now=None):
    """Caller holds Business row lock; catch-up also protects new purchases."""
    now = as_utc(now or utcnow())
    day = now.astimezone(ZoneInfo(business.timezone)).date()
    deadline = closing_at(business, day)
    if deadline is None:
        return False
    if now < deadline:
        # Catch up after downtime across midnight, but do not undo a manual
        # opening today or a reopening after yesterday's processed closure.
        previous_day = day - timedelta(days=1)
        previous_deadline = closing_at(business, previous_day)
        if (previous_deadline is None or business.last_auto_close_date == previous_day
                or as_utc(business.updated_at) > previous_deadline):
            return False
        day = previous_day
    if business.last_auto_close_date == day:
        return False
    business.last_auto_close_date = day
    if business.is_open:
        business.is_open = False
        business.version += 1
        business.updated_at = now
        emit_event(db, f'business:{business.id}', 'business.updated', {
            'id': business.id, 'version': business.version, 'updatedAt': iso(now), 'isOpen': False,
        })
        notify_business_closed(db, business)
    return True


def validate_schedule(business, scheduled, now):
    if scheduled is None:
        return None
    require(scheduled.tzinfo is not None, 422, 'INVALID_SCHEDULE', 'Incluye la zona horaria de recogida.')
    scheduled = scheduled.astimezone(timezone.utc)
    now = as_utc(now)
    zone = ZoneInfo(business.timezone)
    require(scheduled >= now + timedelta(minutes=5), 422, 'INVALID_SCHEDULE',
            'Programa la recogida con al menos cinco minutos de anticipación.')
    require(scheduled.astimezone(zone).date() == now.astimezone(zone).date(), 422,
            'INVALID_SCHEDULE', 'La recogida programada debe ser hoy en la zona del negocio.')
    deadline = closing_at(business, scheduled.astimezone(zone).date())
    require(deadline is None or scheduled < deadline, 422, 'PICKUP_AFTER_CLOSING',
            'La recogida debe ser anterior al cierre conocido.')
    return scheduled


def enforce_featured_limit(db, business_id, featured, product_id=None):
    """Caller locks Business before Product; count nondeleted even when sold out."""
    if not featured:
        return
    statement = select(func.count()).select_from(Product).where(
        Product.business_id == business_id, Product.is_deleted.is_(False), Product.is_featured.is_(True))
    if product_id:
        statement = statement.where(Product.id != product_id)
        current = db.get(Product, product_id)
        # Preserve pre-existing over-limit flags; only a new highlight is denied.
        if current is not None and current.is_featured:
            return
    require(db.scalar(statement) < 3, 409, 'FEATURED_LIMIT_REACHED',
            'El negocio admite hasta tres productos destacados. Retira uno antes de añadir otro.')


def reserve_voucher(db, order, now):
    day = as_utc(now).astimezone(CAMPUS_ZONE).date()
    require(order.scheduled_pickup_time is None or
            as_utc(order.scheduled_pickup_time).astimezone(CAMPUS_ZONE).date() == day,
            422, 'INVALID_VOUCHER_DATE', 'El vale corresponde al día actual del campus.')
    # User lock in order creation serializes reservations across all businesses.
    used = db.scalar(select(MealVoucherUse.id).where(MealVoucherUse.user_id == order.student_id,
            MealVoucherUse.local_date == day, MealVoucherUse.state.in_(('reserved', 'consumed'))))
    require(used is None, 409, 'MEAL_VOUCHER_ALREADY_USED', 'Ya existe una reserva o uso de vale para hoy.')
    db.add(MealVoucherUse(user_id=order.student_id, order_id=order.id, local_date=day))


def consume_voucher(db, order, now):
    if order.payment_method != 'ValeComida':
        return
    voucher = db.scalar(select(MealVoucherUse).where(MealVoucherUse.order_id == order.id).with_for_update())
    require(voucher is not None and voucher.state == 'reserved', 409, 'MEAL_VOUCHER_NOT_RESERVED')
    require(voucher.local_date == as_utc(now).astimezone(CAMPUS_ZONE).date(), 422,
            'MEAL_VOUCHER_DATE_EXPIRED', 'El vale reservado pertenece a otro día del campus.')
    voucher.state, voucher.updated_at = 'consumed', now


def release_voucher(db, order, actor, now=None):
    require(actor.role == 'business' and actor.business_id == order.business_id, 403, 'FORBIDDEN')
    require(order.status == 'cancelled', 409, 'ORDER_NOT_CANCELLED')
    voucher = db.scalar(select(MealVoucherUse).where(MealVoucherUse.order_id == order.id).with_for_update())
    require(voucher is not None, 404, 'MEAL_VOUCHER_NOT_FOUND')
    require(voucher.state != 'consumed', 409, 'MEAL_VOUCHER_CONSUMED')
    if voucher.state == 'released':
        return False
    voucher.state, voucher.updated_at = 'released', now or utcnow()
    audit_event(db, actor_id=actor.id, action='meal_voucher.released', target_type='order', target_id=order.id,
                data={'notRedeemedConfirmed': True})
    return True
