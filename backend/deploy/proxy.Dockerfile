FROM caddy:2-alpine
RUN mkdir -p /data /config \
    && chown -R 10001:10001 /data /config
COPY --chown=10001:10001 deploy/Caddyfile /etc/caddy/Caddyfile
USER 10001:10001
EXPOSE 8080 8443 8443/udp
