#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${1:?APP_NAME required}"
APP_HOME="${2:-/opt/apps/$APP_NAME}"
SERVICE_NAME="${3:-$APP_NAME}"
RUN_USER="${4:-appsrv}"

RELEASES_DIR="$APP_HOME/releases"

if [[ ! -L "$APP_HOME/current" ]]; then
  echo "[rollback] ERROR: $APP_HOME/current is not a symlink"
  exit 1
fi

CURRENT_TARGET="$(readlink -f "$APP_HOME/current")"
echo "[rollback] current -> $CURRENT_TARGET"

# Find most recent release directory excluding current target
PREV_RELEASE="$(ls -1dt "$RELEASES_DIR"/* 2>/dev/null | grep -v "$CURRENT_TARGET" | head -n 1 || true)"

if [[ -z "${PREV_RELEASE}" ]]; then
  echo "[rollback] ERROR: No previous release found"
  exit 1
fi

echo "[rollback] switching current -> $PREV_RELEASE"
sudo ln -sfn "$PREV_RELEASE" "$APP_HOME/current"
sudo chown -h "$RUN_USER:$RUN_USER" "$APP_HOME/current"

sudo systemctl restart "$SERVICE_NAME"
echo "[rollback] restarted service: $SERVICE_NAME"
