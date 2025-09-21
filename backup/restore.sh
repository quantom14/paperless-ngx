#!/bin/bash
set -euo pipefail

# --- Directories ---
BACKUP_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_SRC_DIR="$(dirname "$BACKUP_SRC_DIR")"
BACKUP_DIR="$BACKUP_SRC_DIR/backups"

# --- Parse command-line options ---
SPECIFIC_BACKUP=""
while getopts ":d:" opt; do
    case $opt in
        d) SPECIFIC_BACKUP="$BACKUP_DIR/$OPTARG" ;;
        \?) echo "[ERROR] Invalid option -$OPTARG"; exit 1 ;;
        :) echo "[ERROR] Option -$OPTARG requires an argument."; exit 1 ;;
    esac
done

# --- Logging ---
LOG_FILE="$BACKUP_SRC_DIR/restore.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "[INFO] Starting restore at $(date)"

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

# --- Determine which backup to restore ---
if [[ -n "$SPECIFIC_BACKUP" ]]; then
    if [[ ! -d "$SPECIFIC_BACKUP" ]]; then
        echo "[ERROR] Specified backup directory does not exist: $SPECIFIC_BACKUP"
        exit 1
    fi
    BACKUP_TO_RESTORE="$SPECIFIC_BACKUP"
else
    BACKUP_TO_RESTORE=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup_*" | sort | tail -n1)
    if [[ -z "$BACKUP_TO_RESTORE" ]]; then
        echo "[ERROR] No backup folders found in $BACKUP_DIR"
        exit 1
    fi
fi

echo "[INFO] Restoring from backup: $BACKUP_TO_RESTORE"

# --- Stop services before restore ---
echo "[INFO] Stopping Paperless-ngx stack..."
docker compose -f "$PROJECT_SRC_DIR/docker-compose.yml" down

# --- Restore volumes ---
for VOL in pgdata data media; do
    echo "[INFO] Restoring $VOL volume..."

    # Extract the files into the volume
    docker run --rm -v paperless-ngx_${VOL}:/volume -v "$BACKUP_TO_RESTORE":/backup alpine \
        sh -c "for f in /backup/${VOL}-*.tar.gz; do
                    echo '[INFO] Extracting' \$f
                    tar xzf \$f --strip 1
               done"
    echo "[INFO] $VOL volume restored."
done

# --- Restore database ---
echo "[INFO] Dropping existing database $POSTGRES_DB if it exists..."
docker compose -f "$PROJECT_SRC_DIR/docker-compose.yml" up -d db
sleep 5
docker compose exec -T db psql -U "$POSTGRES_USER" -d postgres -c "DROP DATABASE IF EXISTS $POSTGRES_DB;"
docker compose exec -T db psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE $POSTGRES_DB;"

echo "[INFO] Restoring PostgreSQL database..."
docker compose exec -T db psql -U "$POSTGRES_USER" "$POSTGRES_DB" < "$BACKUP_TO_RESTORE"/db-*.sql
echo "[INFO] Database restored."

# --- Start services ---
echo "[INFO] Starting Paperless-ngx stack..."
docker compose -f "$PROJECT_SRC_DIR/docker-compose.yml" up -d
echo "[INFO] Restore completed successfully at $(date)."
