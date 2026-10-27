#!/bin/sh
# Startup script for the Base44 sandbox (docker-compose.base44.yml).
#
# 1. Seeds/merges the local config overrides: sandbox wiring and the instance
#    settings the file already holds.
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
#
# config/local-<NODE_ENV>.json is the repository's documented way to override
# the configuration locally, and it is gitignored. Besides that sandbox wiring it
# holds the instance settings (name, descriptions, terms, policies...), so it is
# never overwritten: it is seeded once from the committed copy below and the
# sandbox wiring is merged into it on every start, keeping every other key.
[ -f config/local-dev.json ] || cp support/docker/base44/instance-config.json config/local-dev.json

node - <<'EOF'
const fs = require('fs')

const file = 'config/local-dev.json'
let config = {}
try { config = JSON.parse(fs.readFileSync(file, 'utf8')) } catch (err) { config = {} }

config.database = { ...config.database, hostname: 'postgres' }
config.redis = { ...config.redis, hostname: 'redis' }

const suffix = process.env.BASE44_PUBLIC_HOST_SUFFIX
if (suffix) {
  config.webserver = { ...config.webserver, hostname: `9000-${suffix}`, port: 443, https: true }
}

fs.writeFileSync(file, JSON.stringify(config, null, 2) + '\n')
EOF

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
