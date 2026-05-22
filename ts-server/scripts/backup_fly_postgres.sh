#!/usr/bin/env bash
set -euo pipefail

# Backup Fly Postgres database by running pg_dump inside the postgres app machine.
# Usage:
#   ./scripts/backup_fly_postgres.sh <postgres_app_name> <db_name> [output_dir]
#
# Example:
#   ./scripts/backup_fly_postgres.sh ts-postgres ts_db ./backups

PG_APP="${1:-}"
DB_NAME="${2:-}"
OUT_DIR="${3:-./backups}"

if [[ -z "$PG_APP" || -z "$DB_NAME" ]]; then
  echo "Thiếu tham số. Usage: $0 <postgres_app_name> <db_name> [output_dir]"
  exit 1
fi

mkdir -p "$OUT_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
OUT_FILE="$OUT_DIR/${PG_APP}_${DB_NAME}_${TS}.dump"

echo "[backup] Creating pg_dump..."
fly ssh console -a "$PG_APP" -C "pg_dump -Fc -d $DB_NAME" > "$OUT_FILE"

echo "[backup] Saved: $OUT_FILE"
