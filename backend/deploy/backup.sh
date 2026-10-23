#!/bin/sh
# Run from backend/ on the Linux deployment host. No destructive restore action.
set -eu
umask 077
destination=${1:?Usage: sh deploy/backup.sh /absolute/off-repository/backup-directory}
case "$destination" in /*) ;; *) echo 'An absolute backup directory is required.' >&2; exit 1 ;; esac
mkdir -p "$destination"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
database_file="$destination/snackup-$stamp.dump"
media_file="$destination/snackup-media-$stamp.tar.gz"
if [ -e "$database_file" ] || [ -e "$media_file" ]; then
    echo 'Backup filename already exists.' >&2
    exit 1
fi
docker compose exec -T db sh -c 'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$database_file"
docker compose run --rm --no-deps -T api tar -C /data/media -czf - . > "$media_file"
sha256sum "$database_file" "$media_file" > "$destination/snackup-$stamp.sha256"
printf '%s\n' 'Backup complete. Copy encrypted files off the server and test restoration in an isolated database.'
