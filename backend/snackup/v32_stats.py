"""Sales aggregates use completion/cancellation dates in the business timezone."""
from datetime import timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

from sqlalchemy import func, select

from .auth import as_utc
from .operation_models import Order, OrderItem, Product
from .operations import _history_filter, _summary


def detailed_summary(db, business, start, end):
    condition = _history_filter(business.id, start, end)
    result = _summary(db, condition)
    zone = ZoneInfo(business.timezone)
    daily = {}
    day, last = start.astimezone(zone).date(), end.astimezone(zone).date()
    while day < last:
        daily[day] = {'date': day, 'completed': 0, 'cancelled': 0, 'totalSold': Decimal('0.00')}
        day += timedelta(days=1)
    statement = select(Order.status, Order.total, Order.completed_at, Order.cancelled_at).where(condition)
    # Stream only scalar columns; no item snapshots, names or identities loaded.
    for status, total, completed, cancelled in db.execute(statement.execution_options(yield_per=500)):
        local = as_utc(completed if status == 'completed' else cancelled).astimezone(zone).date()
        daily[local][status] += 1
        if status == 'completed':
            daily[local]['totalSold'] += total
    sales = select(Order.id).where(condition, Order.status == 'completed')
    top = db.execute(select(OrderItem.product_id, Product.name, func.sum(OrderItem.quantity),
        func.sum(OrderItem.price * OrderItem.quantity)).join(Product, Product.id == OrderItem.product_id)
        .where(OrderItem.order_id.in_(sales)).group_by(OrderItem.product_id, Product.name)
        .order_by(func.sum(OrderItem.quantity).desc(), OrderItem.product_id).limit(10))
    payments = db.execute(select(Order.payment_method, func.count(), func.sum(Order.total))
        .where(condition, Order.status == 'completed').group_by(Order.payment_method).order_by(Order.payment_method))
    by_payment = {}
    for method, count, total in payments:
        method = 'Efectivo' if method == 'cash' else method
        entry = by_payment.setdefault(method, {'paymentMethod': method, 'completed': 0, 'totalSold': Decimal('0.00')})
        entry['completed'] += count
        entry['totalSold'] += total
    return {**result, 'timezone': business.timezone, 'daily': list(daily.values()),
            'topProducts': [{'productId': id, 'name': name, 'quantity': qty, 'totalSold': total}
                            for id, name, qty, total in top], 'paymentMethods': list(by_payment.values())}
