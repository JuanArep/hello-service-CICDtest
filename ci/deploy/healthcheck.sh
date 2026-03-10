#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${1:?APP_NAME required}"
APP_HOME="${2:-/opt/apps/$APP_NAME}"

ENV_FILE="$APP_HOME/current/app.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

HEALTH_URL="${HEALTH_URL:-http://localhost:8081/actuator/health}"

echo "[healthcheck] URL=$HEALTH_URL"

# Wait up to 60 seconds (30 * 2s)
for i in {1..30}; do
  if curl -fsS "$HEALTH_URL" > /dev/null 2>&1; then
    echo "[healthcheck] OK"
    exit 0
  fi
  echo "[healthcheck] waiting... ($i/30)"
  sleep 2
done

echo "[healthcheck] FAILED"
exit 1