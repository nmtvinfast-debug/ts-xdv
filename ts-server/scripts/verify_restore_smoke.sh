#!/usr/bin/env bash
set -euo pipefail

# Smoke verify after restore (runs login and basic endpoints on a given base URL).
# Usage:
#   BASE_URL=https://<app>.fly.dev ./scripts/verify_restore_smoke.sh

BASE_URL="${BASE_URL:-http://localhost:3000}"

echo "[verify] BASE_URL=$BASE_URL"
echo "[verify] Login..."
TOKEN=$(curl -sS "$BASE_URL/api/auth/login"   -H "content-type: application/json"   -d '{"username":"ketoan_demo","password":"Demo@123456"}' | node -p "JSON.parse(fs.readFileSync(0,'utf8')).accessToken || ''" || true)

if [[ -z "$TOKEN" ]]; then
  echo "[verify] Login failed (no token). Bạn cần seed demo trước."
  exit 1
fi

TODAY="$(date +%Y-%m-%d)"
echo "[verify] Reports daily..."
curl -sS "$BASE_URL/api/reports/accounting/daily?date=$TODAY" -H "authorization: Bearer $TOKEN" | head -c 500 || true

echo
echo "[verify] OK"
