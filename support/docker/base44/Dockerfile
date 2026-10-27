# Development image used by docker-compose.base44.yml (Base44 sandbox).
#
# It only provides the operating-system level dependencies required to *run*
# PeerTube from source, mirroring support/docker/production/Dockerfile:
# FFmpeg and ffprobe for transcoding/storyboards, OpenSSL, and the build
# toolchain needed by native Node modules.
#
# The application source is deliberately NOT copied: the compose file mounts the
# checkout and installs the JavaScript dependencies from pnpm-lock.yaml at
# startup, so source edits are picked up by the dev servers without rebuilding.
FROM node:22

RUN apt-get update \
 && apt-get install -y --no-install-recommends openssl ffmpeg python3 ca-certificates curl git build-essential \
 && rm -rf /var/lib/apt/lists/*

# Version pinned by the "packageManager" field of package.json (the same one CI
# resolves through pnpm/action-setup), so lockfile handling matches CI.
RUN npm install -g pnpm@10.15.1

WORKDIR /app
