#!/bin/sh
# Build a self-contained, downloadable copy of this PeerTube instance.
#
# The archive holds the whole runnable source tree (what `docker-compose.base44.yml`
# needs to boot), minus anything regenerated (node_modules, .git, builds, caches) or
# huge (installed plugins), plus:
#   - config/local-dev.json with webserver.hostname pointing at localhost:9000 instead
#     of the sandbox proxy, so streams and images work on the user's own machine, and
#     keeping the instance settings (name, descriptions, terms, logo...)
#   - start/stop launchers for Windows and macOS/Linux
#   - START-HERE.md with the instructions
#
# Output: backups/bundles/peertube-local.zip (gitignored, served by the `downloads`
# service of docker-compose.base44.yml on port 8080).
#
# Usage, from the repository root:
#   sh support/docker/base44/make-bundle.sh
set -eu

root=$(cd "$(dirname "$0")/../../.." && pwd)
out="$root/backups/bundles"
tmp=$(mktemp -d)
pkg="$tmp/peertube-local"

mkdir -p "$pkg" "$out"
trap 'rm -rf "$tmp"' EXIT

# Source tree. storage/ is kept (avatars, uploaded files) but not its caches, logs,
# temporary files or the plugin node_modules.
tar -C "$root" -cf - \
  --exclude=.git \
  --exclude=node_modules \
  --exclude=.pnpm-store \
  --exclude=.base44 \
  --exclude=./backups \
  --exclude=dist \
  --exclude=./storage/plugins \
  --exclude=./storage/logs \
  --exclude=./storage/cache \
  --exclude=./storage/tmp \
  --exclude=./storage/tmp-persistent \
  --exclude=./storage/bin \
  --exclude=./config/local-dev.json \
  --exclude=./config/production.yaml \
  --exclude=./dev1 \
  --exclude='*.zip' \
  . | tar -C "$pkg" -xf -

# The sandbox wiring of config/local-dev.json (proxy hostname, https, port 443) is
# replaced with the addresses of a normal local install. Everything else in that file
# is the instance identity and is carried over.
python3 - "$root/config/local-dev.json" "$pkg/config/local-dev.json" <<'PY'
import json, sys

source, target = sys.argv[1], sys.argv[2]
with open(source, encoding="utf-8") as handle:
    config = json.load(handle)

config["webserver"] = {"hostname": "localhost", "port": 9000, "https": False}

with open(target, "w", encoding="utf-8") as handle:
    json.dump(config, handle, indent=2, ensure_ascii=False)
    handle.write("\n")
PY

cat > "$pkg/START-HERE.md" <<'DOC'
# Windows 7 (PeerTube) — run it on your own computer

This folder is a complete copy of your video site. It runs with Docker, so nothing
is installed on your computer: everything stays inside Docker and inside this folder.

## What you need

- **Docker Desktop** — https://www.docker.com/products/docker-desktop
  (free; Windows 10/11 with WSL 2, macOS, or Linux)
- About 6 GB of free disk space, and an internet connection for the first start.

## Start it

**Windows** — double-click `start-windows.bat` and wait. The first start builds the
app and downloads its dependencies, which takes 15–30 minutes. When it is ready your
browser opens http://localhost:3000. Later starts take seconds.

**macOS / Linux** — open a terminal in this folder and run:

```sh
sh start.sh
```

Then open http://localhost:3000 in your browser.

## Stop it

`stop-windows.bat` (Windows) or `sh stop.sh` (macOS/Linux). Nothing is lost: settings
and uploads stay in the `storage/` folder and in a Docker volume.

## Sign in

The built-in developer account is:

- user: `root`
- password: `test`

Your own account, and the videos you upload here, live in the database — that part is
not in this folder, so on your machine you start with `root` / `test` and can create
your account again from the sign-up page. Your site name, descriptions, terms, code of
conduct and logo are included.

## About .exe and .apk

There is no `.exe` program and no `.apk` app, because PeerTube is not a desktop or
phone app — it is a website. It runs on the computer that hosts it (this folder,
started by the `.bat` file) and every other device just opens the address in a browser:

- on your computer: http://localhost:3000
- on your phone, on the same Wi-Fi: `http://<your-computer-ip>:3000`

`start-windows.bat` is the file to double-click — it does what an `.exe` would do,
without installing an unsigned program. Nothing is added to your Start menu and the
registry is not touched: delete this folder (and `docker compose down` first) and it is
all gone.

## If something does not start

```sh
docker compose -f docker-compose.base44.yml ps
docker compose -f docker-compose.base44.yml logs --tail 100 peertube
```

The usual causes are Docker Desktop not running, or port 3000 already used by another
program.

## Backing it up

```sh
sh support/docker/base44/backup.sh
```

writes the database and `storage/` into `backups/`. Keep that archive somewhere safe.
DOC

cat > "$pkg/start-windows.bat" <<'BAT'
@echo off
setlocal
cd /d "%~dp0"

where docker >nul 2>nul
if errorlevel 1 (
  echo Docker Desktop is not installed. Get it from https://www.docker.com/products/docker-desktop
  pause
  exit /b 1
)

echo Starting Windows 7 ^(PeerTube^). The first start takes 15-30 minutes...
docker compose -f docker-compose.base44.yml up -d --build
if errorlevel 1 (
  echo Could not start. Is Docker Desktop running?
  pause
  exit /b 1
)

echo Waiting for the site to answer...
set tries=0
:wait
powershell -NoProfile -Command "try { $r = Invoke-WebRequest -UseBasicParsing http://localhost:3000/ -TimeoutSec 5; if ($r.StatusCode -eq 200) { exit 0 } else { exit 1 } } catch { exit 1 }"
if errorlevel 1 (
  set /a tries+=1
  if %tries% geq 240 (
    echo Still not answering. Check: docker compose -f docker-compose.base44.yml logs peertube
    pause
    exit /b 1
  )
  timeout /t 5 /nobreak >nul
  goto wait
)

echo Ready: http://localhost:3000
start "" http://localhost:3000
pause
BAT

cat > "$pkg/stop-windows.bat" <<'BAT'
@echo off
cd /d "%~dp0"
docker compose -f docker-compose.base44.yml down
echo Stopped. Your data is kept.
pause
BAT

cat > "$pkg/start.sh" <<'SH'
#!/bin/sh
# Start Windows 7 (PeerTube) locally. The first run takes 15-30 minutes.
set -eu
cd "$(dirname "$0")"

command -v docker >/dev/null 2>&1 || {
  echo "Docker is not installed. Get it from https://www.docker.com/products/docker-desktop"
  exit 1
}

docker compose -f docker-compose.base44.yml up -d --build
echo "Waiting for the site to answer (the first start is slow)..."

tries=0
while ! curl -sf -o /dev/null http://localhost:3000/; do
  tries=$((tries + 1))
  if [ "$tries" -ge 240 ]; then
    echo "Still not answering. Check: docker compose -f docker-compose.base44.yml logs peertube"
    exit 1
  fi
  sleep 5
done

echo "Ready: http://localhost:3000"
SH

cat > "$pkg/stop.sh" <<'SH'
#!/bin/sh
set -eu
cd "$(dirname "$0")"
docker compose -f docker-compose.base44.yml down
echo "Stopped. Your data is kept."
SH

chmod +x "$pkg/start.sh" "$pkg/stop.sh"

rm -f "$out/peertube-local.zip"
python3 -m zipfile -c "$out/peertube-local.zip" "$pkg"
ls -lh "$out/peertube-local.zip"
