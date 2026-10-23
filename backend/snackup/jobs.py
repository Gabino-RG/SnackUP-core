"""One supervised scheduler process; PostgreSQL advisory lock across replicas."""
from datetime import timedelta
from pathlib import Path
import signal
import sys
from threading import Event, Lock

from sqlalchemy import select, text

from .auth import as_utc
from .common import iso
from .db import Database, emit_event, utcnow
from .operation_models import Business, Order
from .v32_chat import TTL, close_chat
from .v32_models import Chat
from .v32_services import close_if_due

LOCAL_LOCK = Lock()
LOCK_ID = 831724932


def run_cycle(database, settings, now=None):
    now = as_utc(now or utcnow())
    counts = {'closures': 0, 'pickupAlerts': 0, 'expiredChats': 0}
    with database.engine.connect() as guard:
        postgres = guard.dialect.name == 'postgresql'
        acquired = guard.scalar(text('SELECT pg_try_advisory_lock(:key)'), {'key': LOCK_ID}) if postgres else LOCAL_LOCK.acquire(False)
        if not acquired:
            return counts
        try:
            # Independent phases avoid Business -> Order lock inversion with
            # transitions. Each phase commits its marker and outbox atomically.
            with database.sessions.begin() as db:
                businesses = db.scalars(select(Business).where(Business.auto_close_enabled.is_(True),
                    Business.is_active.is_(True)).order_by(Business.id).with_for_update()).all()
                for business in businesses:
                    counts['closures'] += int(close_if_due(db, business, now))
            with database.sessions.begin() as db:
                orders = db.scalars(select(Order).where(Order.status.in_(('pending', 'accepted', 'preparing', 'ready')),
                    Order.scheduled_pickup_time > now, Order.scheduled_pickup_time <= now + timedelta(minutes=10),
                    Order.pickup_soon_notified_at.is_(None)).order_by(Order.id).with_for_update()).all()
                for order in orders:
                    order.pickup_soon_notified_at = now
                    emit_event(db, f'business:{order.business_id}:orders', 'order.pickup_soon', {
                        'id': order.id, 'businessId': order.business_id, 'scheduledPickupTime': iso(order.scheduled_pickup_time),
                        'status': order.status, 'version': order.version,
                    })
                    counts['pickupAlerts'] += 1
            with database.sessions.begin() as db:
                chats = db.scalars(select(Chat).where(Chat.last_activity_at <= now - TTL)
                                   .order_by(Chat.id).with_for_update()).all()
                for chat in chats:
                    close_chat(db, chat, settings, now)
                    counts['expiredChats'] += 1
        finally:
            if postgres:
                guard.execute(text('SELECT pg_advisory_unlock(:key)'), {'key': LOCK_ID})
            else:
                LOCAL_LOCK.release()
    return counts


def main():
    from .config import Settings
    # Ensure all referenced tables are registered, including push/identity.
    from . import admin_models, identity_models, push_models, review_models  # noqa: F401
    settings = Settings()
    database = Database(settings)
    stop = Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    try:
        while not stop.is_set():
            # Fail the process on a failed cycle. The unified supervisor restarts
            # the complete stack, and no healthy heartbeat hides a stalled job.
            run_cycle(database, settings)
            Path('/tmp/snackup-jobs-heartbeat').touch()
            stop.wait(60)
    except Exception as error:
        # SQL errors can include parameters; emit operational metadata only.
        print('SnackUP scheduled jobs failed: ' + type(error).__name__, file=sys.stderr)
        return 1
    finally:
        database.dispose()


if __name__ == '__main__':
    sys.exit(main())
