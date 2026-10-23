FROM caddy:2.11.7-alpine
ARG CADDY_CONFIG=deploy/Caddyfile
RUN if [ -n "$(getcap /usr/bin/caddy)" ]; then setcap -r /usr/bin/caddy; fi \
    && mkdir -p /data /config \
    && chown -R 10001:10001 /data /config
COPY --chown=10001:10001 ${CADDY_CONFIG} /etc/caddy/Caddyfile
USER 10001:10001
EXPOSE 8080 8443 8443/udp
