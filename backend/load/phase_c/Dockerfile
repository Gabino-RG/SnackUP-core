FROM caddy:2.11.7-alpine AS proxy
RUN if [ -n "$(getcap /usr/bin/caddy)" ]; then setcap -r /usr/bin/caddy; fi
FROM python:3.12-slim-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends redis-server ca-certificates && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 snackup && useradd --uid 10001 --gid 10001 --no-create-home snackup \
    && mkdir -p /data/media /data/redis /data/caddy /srv/usuarios /srv/paneles && chown -R 10001:10001 /data
WORKDIR /app
COPY requirements.lock .
RUN pip install --no-cache-dir -r requirements.lock
COPY --from=proxy /usr/bin/caddy /usr/local/bin/caddy
COPY snackup snackup
COPY contracts contracts
COPY migrations migrations
COPY alembic.ini .
COPY deploy/unified deploy/unified
COPY load/phase_c/Caddyfile deploy/unified/Caddyfile
# Performance image uses the actual proxy/supervisor/API; Flutter builds are checked separately.
RUN printf '<base href="/"><script src="flutter_bootstrap.js"></script>' > /srv/usuarios/index.html \
    && printf '<base href="/paneles/"><script src="flutter_bootstrap.js"></script>' > /srv/paneles/index.html
ENV SNACKUP_MEDIA_DIR=/data/media XDG_DATA_HOME=/data/caddy XDG_CONFIG_HOME=/tmp/caddy
USER 10001:10001
HEALTHCHECK --interval=5s --timeout=8s --start-period=45s --retries=12 CMD ["python", "deploy/unified/healthcheck.py"]
ENTRYPOINT ["python", "deploy/unified/run.py"]
