#!/bin/bash
set -euo pipefail

# --- Config ---
DEPLOYMENT_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_SRC_DIR="$(dirname "$DEPLOYMENT_SRC_DIR")"
COMPOSE_FILE="$PROJECT_SRC_DIR/docker-compose.yml"
CONTAINER_NAME="paperless-ngx-webserver-1"
MAX_WAIT=300
SLEEP_INTERVAL=5  # seconds between checks

echo "[INFO] Starting deployment at $(date)"

# --- Stop services if running ---
if docker compose -f "$COMPOSE_FILE" ps --services --filter "status=running" | grep -q .; then
    echo "[INFO] Stopping running services..."
    docker compose -f "$COMPOSE_FILE" down
else
    echo "[INFO] No running services detected."
fi

# --- Pull latest code ---
echo "[INFO] Pulling latest code from GitHub..."
cd "$PROJECT_SRC_DIR"
# Ensure we’re on the right branch and pull
git fetch --all
git checkout "main"
git pull --rebase origin "main"

# --- Start services ---
echo "[INFO] Starting services..."
docker compose -f "$COMPOSE_FILE" up -d

# --- Wait for webserver health check ---
echo "[INFO] Waiting for $CONTAINER_NAME to become healthy..."
SECONDS_WAITED=0
while true; do
    STATUS=$(docker ps --filter "name=$CONTAINER_NAME" --format "{{.Status}}")
    if [[ "$STATUS" == *"(healthy)"* ]]; then
        echo "[INFO] ✅ $CONTAINER_NAME is healthy after $SECONDS_WAITED seconds."
        break
    elif [[ $SECONDS_WAITED -ge $MAX_WAIT ]]; then
        echo "[ERROR] ❌ Timed out after $MAX_WAIT seconds. Current status: $STATUS"
        exit 1
    else
        echo "[INFO] Current status: $STATUS (waiting...)"
        sleep $SLEEP_INTERVAL
        SECONDS_WAITED=$((SECONDS_WAITED + SLEEP_INTERVAL))
    fi
done

echo "[INFO] Deployment completed successfully at $(date)"
