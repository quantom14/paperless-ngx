#!/bin/bash
set -euo pipefail

BACKUP_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_SRC_DIR="$(dirname "$BACKUP_SRC_DIR")"

# --- Logging ---
LOG_FILE="$BACKUP_SRC_DIR/backup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "[INFO] Starting backup at $(date)"

# --- Rotate log if too big ---
MAX_SIZE=$((10 * 1024 * 1024)) # 10 MB
if [ -f "$LOG_FILE" ]; then
    if stat --version >/dev/null 2>&1; then
        FILE_SIZE=$(stat -c%s "$LOG_FILE")  # Linux
    else
        FILE_SIZE=$(stat -f%z "$LOG_FILE")  # macOS/BSD
    fi
    if [ "$FILE_SIZE" -gt "$MAX_SIZE" ]; then
        echo "[INFO] Log file exceeded 10 MB, rotating..."
        mv "$LOG_FILE" "$LOG_FILE.$(date +%Y%m%d-%H%M%S)"
        touch "$LOG_FILE"
    fi
fi

# --- Load environment ---
echo "[INFO] Loading environment variables from .env file"
set -a
source "$PROJECT_SRC_DIR/.env"
set +a

# --- Timestamped backup folder ---
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$BACKUP_SRC_DIR/backups/backup_$TIMESTAMP"
mkdir -p "$BACKUP_DIR"
echo "[INFO] Backup folder created at $BACKUP_DIR"

# --- Backup PostgreSQL database ---
echo "[INFO] Dumping PostgreSQL database..."
docker compose -f "$PROJECT_SRC_DIR/docker-compose.yml" exec -T db \
    pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > "$BACKUP_DIR/db-$TIMESTAMP.sql"
echo "[INFO] Database dump completed."

# --- Backup volumes ---
for VOL in pgdata data media; do
    echo "[INFO] Archiving $VOL volume..."
    docker run --rm -v paperless-ngx_${VOL}:/volume -v "$BACKUP_DIR":/backup \
        alpine sh -c "cd /volume && tar czf /backup/${VOL}-$TIMESTAMP.tar.gz ."
    echo "[INFO] $VOL volume backup completed."
done

# --- Cleanup old backups (keep last 180) ---
MAX_BACKUPS=180
echo "[INFO] Cleaning up old backups, keeping last $MAX_BACKUPS"
BACKUP_DIRS=()
while IFS= read -r dir; do
    BACKUP_DIRS+=("$dir")
done < <(find "$BACKUP_SRC_DIR/backups" -maxdepth 1 -type d -name "backup_*" | sort)

NUM_BACKUPS=${#BACKUP_DIRS[@]}
if [ "$NUM_BACKUPS" -lt "$MAX_BACKUPS" ]; then
    echo "[INFO] Found only $NUM_BACKUPS backups so none will be deleted"
else
    NUM_TO_DELETE=$((NUM_BACKUPS - MAX_BACKUPS))
    echo "[INFO] Deleting $NUM_TO_DELETE old backup(s)"
    for OLD in "${BACKUP_DIRS[@]:0:$NUM_TO_DELETE}"; do
        echo "[INFO] Removing $OLD"
        rm -rf "$OLD"
    done
fi

echo "[INFO] Backup completed successfully at $(date). All files are in $BACKUP_DIR"
