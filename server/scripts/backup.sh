#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# Load production env for DB connection string
set -a
source .env.production
set +a

BACKUP_DIR="$PROJECT_DIR/backups"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RETENTION_DAYS=7

mkdir -p "$BACKUP_DIR"

echo "========================================"
echo " Field Tracker - Database Backup"
echo "========================================"
echo " Timestamp: $TIMESTAMP"
echo " Backup to: $BACKUP_DIR"

# --- PostgreSQL backup ---
if [ -n "${DATABASE_URL:-}" ]; then
  BACKUP_FILE="$BACKUP_DIR/fieldtracker_db_$TIMESTAMP.sql.gz"
  echo "[1/2] Dumping PostgreSQL database..."
  pg_dump "$DATABASE_URL" | gzip > "$BACKUP_FILE"
  echo "      -> $BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1))"
elif [ -n "${PGHOST:-}" ]; then
  BACKUP_FILE="$BACKUP_DIR/fieldtracker_db_$TIMESTAMP.sql.gz"
  echo "[1/2] Dumping PostgreSQL database ($PGDATABASE)..."
  pg_dump -h "$PGHOST" -p "${PGPORT:-5432}" -U "${PGUSER:-postgres}" -d "${PGDATABASE:-field_tracker}" | gzip > "$BACKUP_FILE"
  echo "      -> $BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1))"
else
  echo "[SKIP] No DATABASE_URL or PGHOST set — skipping database backup."
fi

# --- Application files backup ---
echo "[2/2] Backing up uploads directory..."
if [ -d "uploads" ] && [ "$(ls -A uploads 2>/dev/null)" ]; then
  UPLOADS_FILE="$BACKUP_DIR/fieldtracker_uploads_$TIMESTAMP.tar.gz"
  tar czf "$UPLOADS_FILE" uploads/
  echo "      -> $UPLOADS_FILE ($(du -h "$UPLOADS_FILE" | cut -f1))"
else
  echo "      -> No uploads to back up."
fi

# --- Clean old backups ---
echo ""
echo "[CLEANUP] Removing backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name 'fieldtracker_*' -type f -mtime "+$RETENTION_DAYS" -delete
echo "          Done."

echo "========================================"
echo " Backup complete!"
echo " Location: $BACKUP_DIR"
echo "========================================"
