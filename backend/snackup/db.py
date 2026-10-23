from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from fastapi import Request
from sqlalchemy import DateTime, Integer, JSON, String, create_engine, event
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker


def utcnow():
    return datetime.now(timezone.utc)


def new_id():
    return uuid4().hex


class Base(DeclarativeBase):
    pass


class OutboxEvent(Base):
    __tablename__ = 'outbox_events'
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    event_id: Mapped[str] = mapped_column(String(32), default=new_id, unique=True)
    topic: Mapped[str] = mapped_column(String(200), index=True)
    event_type: Mapped[str] = mapped_column(String(80))
    data: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)


def emit_event(db, topic, event_type, data):
    db.add(OutboxEvent(topic=topic, event_type=event_type, data=data))


class Database:
    def __init__(self, settings):
        kwargs = {'pool_pre_ping': True}
        if settings.database_url.startswith('sqlite'):
            kwargs['connect_args'] = {'check_same_thread': False, 'timeout': 15}
            if settings.database_url == 'sqlite://':
                from sqlalchemy.pool import StaticPool
                kwargs['poolclass'] = StaticPool
            elif settings.database_url.startswith('sqlite:///'):
                Path(settings.database_url.removeprefix('sqlite:///')).parent.mkdir(parents=True, exist_ok=True)
        else:
            kwargs.update(pool_size=settings.pool_size, max_overflow=settings.max_overflow, pool_timeout=10)
        self.engine = create_engine(settings.database_url, **kwargs)
        if self.engine.dialect.name == 'sqlite':
            @event.listens_for(self.engine, 'connect')
            def configure_sqlite(connection, _):
                cursor = connection.cursor()
                cursor.execute('PRAGMA foreign_keys=ON')
                cursor.execute('PRAGMA busy_timeout=15000')
                cursor.close()
        self.sessions = sessionmaker(self.engine, expire_on_commit=False, autoflush=True)

    def dispose(self):
        self.engine.dispose()


def get_db(request: Request):
    with request.app.state.db.sessions() as session:
        with session.begin():
            yield session
