#!/bin/sh
# Startup script for the Base44 sandbox (docker-compose.base44.yml).
#
# 1. Writes the local config overrides the sandbox needs.
# 2. Installs the JavaScript dependencies from the lockfile (the workspace is
#    bind-mounted, so node_modules cannot be baked into the image).
# 3. Hands over to PeerTube's own development workflow: `npm run dev` runs the
#    Angular dev server on port 3000 and the Express API on port 9000, both with
#    live reload.
set -eu

# config/dev.yaml expects PostgreSQL/Redis on 127.0.0.1: in the sandbox they are
# separate compose services. It also builds absolute URLs (video streams,
# thumbnails, downloads, tracker, oEmbed...) from webserver.hostname, which has
# to be the public address of the sandbox proxy instead of localhost, otherwise
# those URLs are not reachable from the browser.
# config/local-<NODE_ENV>.json is the repository's documented way to override
# the configuration locally, and it is gitignored.
if [ -n "${BASE44_PUBLIC_HOST_SUFFIX:-}" ]; then
  cat > config/local-dev.json <<EOF
{
  "database": { "hostname": "postgres" },
  "redis": { "hostname": "redis" },
  "webserver": { "hostname": "9000-${BASE44_PUBLIC_HOST_SUFFIX}", "port": 443, "https": true }
}
EOF
else
  cat > config/local-dev.json <<EOF
{
  "database": { "hostname": "postgres" },
  "redis": { "hostname": "redis" }
}
EOF
fi

pnpm install --frozen-lockfile

# The API serves the client static files from client/dist
# (server/core/controllers/client.ts), and the dev workflow only copies the
# locales there (scripts/dev/server.sh) while the production server build also
# copies the assets (scripts/build/server.sh). Without this copy the default
# instance logos, built as absolute
# webserver.hostname/client/assets/images/... URLs, answer 404.
mkdir -p client/dist
rm -rf client/dist/assets
cp -r client/src/assets client/dist/assets

exec npm run dev
