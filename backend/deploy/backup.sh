#!/bin/sh
# Run from backend/ on the Linux deployment host. No destructive restore action.
set -eu
umask 077
layout=separate
if [ "${1:-}" = --unified ]; then layout=unified; shift; fi
destination=${1:?Usage: sh deploy/backup.sh [--unified] /absolute/off-repository/backup-directory}
case "$destination" in /*) ;; *) echo 'An absolute backup directory is required.' >&2; exit 1 ;; esac
mkdir -p "$destination"
destination=$(cd "$destination" && pwd -P)
checkout=$(cd .. && pwd -P)
case "$destination/" in "$checkout/"*) echo 'Use a directory outside the checkout.' >&2; exit 1 ;; esac
stamp=$(date -u +%Y%m%dT%H%M%SZ)
database_file="$destination/snackup-$stamp.dump"
media_file="$destination/snackup-media-$stamp.tar.gz"
if [ -e "$database_file" ] || [ -e "$media_file" ]; then
    echo 'Backup filename already exists.' >&2
    exit 1
fi
if [ "$layout" = unified ]; then
    docker compose -f compose.unified.yaml exec -T db sh -c 'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$database_file"
    docker compose -f compose.unified.yaml exec -T app tar -C /data/media -czf - . > "$media_file"
else
    docker compose exec -T db sh -c 'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$database_file"
    docker compose run --rm --no-deps -T api tar -C /data/media -czf - . > "$media_file"
fi
sha256sum "$database_file" "$media_file" > "$destination/snackup-$stamp.sha256"
printf '%s\n' 'Backup complete. Copy encrypted files off the server and test restoration in an isolated database.'
