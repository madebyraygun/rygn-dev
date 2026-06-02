#!/usr/bin/env bash
set -euo pipefail

# Build the site locally, then mirror _site/ to the server over rsync.
#
# Cache busting is handled at build time: the stylesheet is served with a
# content-hash query (/static/style.css?v=<hash>) that changes whenever the
# CSS changes, so each deploy invalidates stale browser copies automatically.
# A clean build + rsync --delete keeps the server an exact mirror of _site/.
#
# Target — override via env if needed:
HOST="${DEPLOY_HOST:-rygn_dev1@5.161.59.79}"
REMOTE_PATH="${DEPLOY_PATH:-/var/www/ffe864fa-c89f-4fba-906d-773cae9668a0/public_html}"
SSH_PORT="${DEPLOY_PORT:-22}"
#
# Usage:
#   ./deploy.sh             build, then deploy        (https://rygn.dev/)
#   ./deploy.sh --dry-run   build, then show what would change (transfers nothing)

dry=
[[ "${1:-}" == "--dry-run" ]] && dry=--dry-run

rm -rf _site
npm run build

rsync -avz --delete ${dry:+"$dry"} \
  -e "ssh -p ${SSH_PORT}" \
  --exclude '.DS_Store' \
  --exclude 'admin' \
  _site/ "${HOST}:${REMOTE_PATH%/}/"

echo "Deployed _site/ → ${HOST}:${REMOTE_PATH%/}/  (https://rygn.dev/)"
