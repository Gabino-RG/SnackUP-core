#!/bin/sh
# Run from the packaged backend/ directory on Linux, during a maintenance window.
set -eu
umask 077
destination=${1:?Usage: sh backup_unified.sh /absolute/private/backup-directory}
case "$destination" in /*) ;; *) echo 'Use an absolute backup directory.' >&2; exit 1 ;; esac
test -f compose.unified.yaml
test -f .env
mkdir -p "$destination"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
target="$destination/snackup-$stamp"
# Atomic directory creation prevents overwrite, even with concurrent invocations.
mkdir "$target"
compose() { docker compose --env-file .env -f compose.unified.yaml -p "${SNACKUP_COMPOSE_PROJECT:-snackup-piloto}" "$@"; }
compose exec -T db sh -c 'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$target/database.dump.partial"
compose exec -T app tar -C /data/media -czf - . > "$target/media.tar.gz.partial"
mv "$target/database.dump.partial" "$target/database.dump"
mv "$target/media.tar.gz.partial" "$target/media.tar.gz"
(cd "$target" && sha256sum database.dump media.tar.gz > SHA256SUMS)
printf '%s\n' 'Backup complete. Copy encrypted off-server and test isolated restoration. Failed backups retain .partial files and must not be used.'
