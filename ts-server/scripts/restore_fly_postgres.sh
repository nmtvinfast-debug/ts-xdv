#!/usr/bin/env bash
set -euo pipefail

# Restore to Fly Postgres using pg_restore inside postgres app.
# WARNING: This can overwrite data depending on options.
# Usage:
#   ./scripts/restore_fly_postgres.sh <postgres_app_name> <db_name> <dump_file>
#
# Example:
#   ./scripts/restore_fly_postgres.sh ts-postgres ts_db ./backups/ts-postgres_ts_db_20260225_120000.dump

PG_APP="${1:-}"
DB_NAME="${2:-}"
DUMP_FILE="${3:-}"

if [[ -z "$PG_APP" || -z "$DB_NAME" || -z "$DUMP_FILE" ]]; then
  echo "Thiếu tham số. Usage: $0 <postgres_app_name> <db_name> <dump_file>"
  exit 1
fi

if [[ ! -f "$DUMP_FILE" ]]; then
  echo "Không tìm thấy file dump: $DUMP_FILE"
  exit 1
fi

echo "[restore] Uploading dump to postgres machine (via stdin)..."
cat "$DUMP_FILE" | fly ssh console -a "$PG_APP" -C "pg_restore --clean --if-exists -d $DB_NAME"

echo "[restore] Done."
