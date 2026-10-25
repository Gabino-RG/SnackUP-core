# syntax=docker/dockerfile:1
# Same pinned Flutter builder used by the backend's published students deployment.
FROM ghcr.io/cirruslabs/flutter:3.32.0@sha256:127a63655668caf704b28d2d2f2bcb7353e431846b3f7c27cf4b230948f3656a AS build
WORKDIR /workspace/app
RUN flutter config --no-analytics --enable-web
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get --enforce-lockfile
COPY lib ./lib
COPY assets ./assets
COPY web ./web
ARG WEB_BASE_HREF=/
ARG API_BASE_URL=
RUN flutter build web --release --no-pub --no-web-resources-cdn --pwa-strategy=none \
      --target lib/main.dart --base-href "$WEB_BASE_HREF" --dart-define="API_BASE_URL=$API_BASE_URL"

FROM caddy:2.11.7-alpine AS runtime
RUN if [ -n "$(getcap /usr/bin/caddy)" ]; then setcap -r /usr/bin/caddy; fi \
    && addgroup -S -g 10001 snackup \
    && adduser -S -D -H -u 10001 -G snackup snackup
COPY --from=build --chown=10001:10001 /workspace/app/build/web /srv
COPY deploy/Caddyfile /etc/caddy/Caddyfile
ENV XDG_CONFIG_HOME=/tmp/caddy-config XDG_DATA_HOME=/tmp/caddy-data
USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=20s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
