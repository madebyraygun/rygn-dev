#!/usr/bin/env bash
set -euo pipefail

# Build the site locally, then mirror _site/ to the server over rsync.
#
# Set your target once via environment (e.g. in ~/.zshrc), or edit the
# two defaults below:
#
#   export DEPLOY_HOST=rygn-dev            # ~/.ssh/config alias or user@host
#   export DEPLOY_PATH=/var/www/rygn-dev   # remote web root
#
# Usage:
#   ./deploy.sh             build, then deploy
#   ./deploy.sh --dry-run   build, then show what would change (transfers nothing)

HOST="${DEPLOY_HOST:-}"
REMOTE_PATH="${DEPLOY_PATH:-}"

if [[ -z "$HOST" || -z "$REMOTE_PATH" ]]; then
  echo "deploy: set DEPLOY_HOST and DEPLOY_PATH first (see the top of deploy.sh)." >&2
  exit 1
fi

dry=()
[[ "${1:-}" == "--dry-run" ]] && dry=(--dry-run)

npm run build

rsync -avz --delete "${dry[@]}" \
  --exclude '.DS_Store' \
  _site/ "${HOST}:${REMOTE_PATH%/}/"

echo "Deployed _site/ → ${HOST}:${REMOTE_PATH%/}/"
