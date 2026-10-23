FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    SNACKUP_MEDIA_DIR=/data/media

WORKDIR /app
COPY requirements.lock ./requirements.lock
RUN python -m pip install --no-cache-dir -r requirements.lock \
    && groupadd --gid 10001 snackup \
    && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin snackup \
    && mkdir -p /data/media \
    && chown -R 10001:10001 /data

COPY --chown=10001:10001 snackup ./snackup
COPY --chown=10001:10001 contracts ./contracts
COPY --chown=10001:10001 migrations ./migrations
COPY --chown=10001:10001 alembic.ini ./alembic.ini
COPY --chown=10001:10001 deploy/healthcheck.py ./deploy/healthcheck.py

USER 10001:10001
EXPOSE 8000
HEALTHCHECK --interval=20s --timeout=5s --start-period=30s --retries=3 \
    CMD ["python", "/app/deploy/healthcheck.py"]
CMD ["uvicorn", "snackup.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000", "--workers", "2", "--no-access-log"]
