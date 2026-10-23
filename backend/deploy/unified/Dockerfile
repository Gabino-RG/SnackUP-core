# syntax=docker/dockerfile:1
# Named contexts are pinned to frontend commits in compose.unified.yaml.
FROM ghcr.io/cirruslabs/flutter:3.32.0@sha256:127a63655668caf704b28d2d2f2bcb7353e431846b3f7c27cf4b230948f3656a AS flutter
RUN apt-get update && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*
RUN flutter config --no-analytics --enable-web
WORKDIR /workspace/app

FROM flutter AS users
COPY --from=usuarios_source /pubspec.yaml /pubspec.lock ./
RUN flutter pub get --enforce-lockfile
COPY --from=usuarios_source /lib ./lib
COPY --from=usuarios_source /assets ./assets
COPY --from=usuarios_source /web ./web
COPY --from=usuarios_source /deploy/check_web_build.py /tools/check_web_build.py
RUN flutter build web --release --no-pub --no-web-resources-cdn --pwa-strategy=none \
      --target lib/main.dart --base-href / \
    && python3 /tools/check_web_build.py build/web --base / --mode firebase

FROM flutter AS panels
COPY --from=paneles_source /app/pubspec.yaml /app/pubspec.lock ./
RUN flutter pub get --enforce-lockfile
COPY --from=paneles_source /app/lib ./lib
COPY --from=paneles_source /app/assets ./assets
COPY --from=paneles_source /app/web ./web
COPY --from=paneles_source /deploy/check_web_build.py /tools/check_web_build.py
RUN flutter build web --release --no-pub --no-web-resources-cdn --pwa-strategy=none \
      --target lib/main_portal_api.dart --base-href /paneles/ \
      --dart-define=BACKEND=rest --dart-define=REVIEW_MODE=false \
      --dart-define=API_BASE_URL=/api/legacy/v1/ \
    && python3 /tools/check_web_build.py build/web --base /paneles/ --mode rest

FROM caddy:2.11.7-alpine AS caddy
FROM python:3.12-slim-bookworm AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 \
    SNACKUP_MEDIA_DIR=/data/media XDG_DATA_HOME=/data/caddy XDG_CONFIG_HOME=/tmp/caddy \
    SNACKUP_USERS_WEB=/srv/usuarios SNACKUP_PANELS_WEB=/srv/paneles
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends redis-server ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 snackup \
    && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin snackup \
    && mkdir -p /data/media /data/redis /data/caddy \
    && chown -R 10001:10001 /data
COPY requirements.lock ./requirements.lock
RUN python -m pip install -r requirements.lock
COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy
COPY --from=users /workspace/app/build/web /srv/usuarios
COPY --from=panels /workspace/app/build/web /srv/paneles
COPY snackup ./snackup
COPY contracts ./contracts
COPY migrations ./migrations
COPY alembic.ini ./alembic.ini
COPY deploy/unified ./deploy/unified
COPY deploy/healthcheck.py ./deploy/healthcheck.py
USER 10001:10001
EXPOSE 8080 8443
HEALTHCHECK --interval=20s --timeout=8s --start-period=120s --retries=3 \
    CMD ["python", "deploy/unified/healthcheck.py"]
ENTRYPOINT ["python", "deploy/unified/run.py"]
CMD ["serve"]
