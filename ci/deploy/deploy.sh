#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${1:?APP_NAME required (e.g., hello-service)}"
ARTIFACT_PATH="${2:?ARTIFACT_PATH required (e.g., target/*.jar)}"
RELEASE_ID="${3:?RELEASE_ID required (e.g., 12_abcd123)}"

APP_HOME="${4:-/opt/apps/$APP_NAME}"
SERVICE_NAME="${5:-$APP_NAME}"
RUN_USER="${6:-appsrv}"

RELEASE_DIR="$APP_HOME/releases/$RELEASE_ID"

echo "[deploy] APP_NAME=$APP_NAME"
echo "[deploy] ARTIFACT_PATH=$ARTIFACT_PATH"
echo "[deploy] RELEASE_ID=$RELEASE_ID"
echo "[deploy] APP_HOME=$APP_HOME"
echo "[deploy] SERVICE_NAME=$SERVICE_NAME"
echo "[deploy] RUN_USER=$RUN_USER"
echo "[deploy] RELEASE_DIR=$RELEASE_DIR"

# Create release folder
sudo mkdir -p "$RELEASE_DIR"

# Copy artifact into the release folder as app.jar
sudo cp -f "$ARTIFACT_PATH" "$RELEASE_DIR/app.jar"

# Ensure app.env exists per release (copy from bootstrap/template)
if [[ -f "$APP_HOME/current/app.env" ]]; then
  sudo cp -f "$APP_HOME/current/app.env" "$RELEASE_DIR/app.env"
elif [[ -f "$APP_HOME/releases/bootstrap/app.env" ]]; then
  sudo cp -f "$APP_HOME/releases/bootstrap/app.env" "$RELEASE_DIR/app.env"
else
  echo "[deploy] ERROR: No app.env found (expected $APP_HOME/current/app.env or $APP_HOME/releases/bootstrap/app.env)"
  exit 1
fi

# Set ownership so the service user can read the release files
sudo chown -R "$RUN_USER:$RUN_USER" "$RELEASE_DIR"

# Atomically switch current symlink to new release
sudo ln -sfn "$RELEASE_DIR" "$APP_HOME/current"
sudo chown -h "$RUN_USER:$RUN_USER" "$APP_HOME/current"

# Restart the systemd service to pick up the new current/app.jar
sudo systemctl restart "$SERVICE_NAME"

echo "[deploy] Restarted service: $SERVICE_NAME"