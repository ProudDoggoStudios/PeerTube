#!/bin/sh
# Snapshot the state of the PeerTube instance running in the Base44 sandbox.
#
# Everything the admin UI saves (instance name/description/terms, users,
# channels, videos, uploaded logos and avatars) lives in the PostgreSQL volume
# and in storage/ of the mounted checkout - never in git. This writes both into
# one archive under backups/ (gitignored) that can be kept outside the sandbox
# or restored into another PeerTube instance.
#
# Usage, from the repository root:
#   sh support/docker/base44/backup.sh
set -eu

compose="docker compose -f docker-compose.base44.yml"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
dir="backups"
sql="$dir/database-$stamp.sql"
archive="$dir/peertube-state-$stamp.tar.gz"

mkdir -p "$dir"
trap 'rm -f "$sql"' EXIT

# --clean --if-exists so the dump can be replayed over an existing database
$compose exec -T postgres pg_dump -U peertube -d peertube_dev --clean --if-exists > "$sql"

# Caches, logs and scratch files are regenerated, so they are left out
# config/local-dev.json holds the instance settings (name, descriptions, terms,
# policies...) next to the sandbox wiring, so it is part of the state as well
tar -czf "$archive" \
  --exclude='storage/cache' \
  --exclude='storage/logs' \
  --exclude='storage/tmp' \
  --exclude='storage/tmp-persistent' \
  --exclude='storage/bin' \
  "$sql" config/local-dev.json storage

echo "Wrote $archive"
