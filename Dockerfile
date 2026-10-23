# syntax=docker/dockerfile:1
FROM ghcr.io/cirruslabs/flutter:3.32.0@sha256:127a63655668caf704b28d2d2f2bcb7353e431846b3f7c27cf4b230948f3656a AS build
WORKDIR /workspace/app
RUN apt-get update && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*
RUN flutter config --no-analytics --enable-web
COPY app/pubspec.yaml app/pubspec.lock ./
RUN flutter pub get --enforce-lockfile
COPY app/lib ./lib
COPY app/assets ./assets
COPY app/web ./web
COPY deploy/check_web_build.py /tools/check_web_build.py
ARG WEB_BASE_HREF=/
ARG API_BASE_URL=/api/legacy/v1/
RUN flutter build web --release --no-pub --no-web-resources-cdn --pwa-strategy=none \
      --target lib/main_portal_api.dart --base-href "$WEB_BASE_HREF" \
      --dart-define=BACKEND=rest --dart-define=REVIEW_MODE=false \
      --dart-define="API_BASE_URL=$API_BASE_URL" \
    && python3 /tools/check_web_build.py build/web --base "$WEB_BASE_HREF" --mode rest

FROM caddy:2.11.7-alpine AS runtime
RUN if [ -n "$(getcap /usr/bin/caddy)" ]; then setcap -r /usr/bin/caddy; fi \
    && addgroup -S -g 10001 snackup \
    && adduser -S -D -H -u 10001 -G snackup snackup
COPY --from=build --chown=10001:10001 /workspace/app/build/web /srv
COPY deploy/Caddyfile deploy/backend-enabled.caddy deploy/backend-disabled.caddy /etc/caddy/
COPY --chmod=755 deploy/entrypoint.sh /usr/local/bin/snackup-web
ENV XDG_CONFIG_HOME=/tmp/caddy-config XDG_DATA_HOME=/tmp/caddy-data
USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
ENTRYPOINT ["/usr/local/bin/snackup-web"]
CMD ["run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
