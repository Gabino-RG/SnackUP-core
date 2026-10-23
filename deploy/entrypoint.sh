#!/bin/sh
set -eu
umask 077

# A deployment operator can select one origin, never a request-controlled proxy.
# Reject credentials, paths, query strings and Caddyfile syntax before expansion.
if [ -n "${SNACKUP_API_UPSTREAM:-}" ]; then
    case "$SNACKUP_API_UPSTREAM" in
        *[!A-Za-z0-9:./-]*)
            printf '%s\n' 'SNACKUP_API_UPSTREAM contains unsupported characters.' >&2
            exit 64
            ;;
    esac
    if ! printf '%s' "$SNACKUP_API_UPSTREAM" | grep -Eq '^https?://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?$'; then
        printf '%s\n' 'SNACKUP_API_UPSTREAM must be an http(s) origin without credentials, path or query.' >&2
        exit 64
    fi
    authority=${SNACKUP_API_UPSTREAM#*://}
    case "$authority" in
        *:*)
            port=${authority##*:}
            if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
                printf '%s\n' 'SNACKUP_API_UPSTREAM port must be between 1 and 65535.' >&2
                exit 64
            fi
            ;;
    esac
    cp /etc/caddy/backend-enabled.caddy /tmp/snackup-backend.caddy
else
    cp /etc/caddy/backend-disabled.caddy /tmp/snackup-backend.caddy
fi

exec caddy "$@"
