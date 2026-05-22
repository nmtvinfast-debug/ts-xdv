# Daily Perf Reports + Regression Alert (12F.12)

## 1) Lưu báo cáo daily vào DB
Table: `perf_http_reports`
- snapshot JSONB
- report_date (YYYY-MM-DD)

Job:
- `PERF_DAILY_REPORT_ENABLED=true`
- `PERF_DAILY_REPORT_INTERVAL_MS=21600000` (6h)

## 2) Regression alert (so sánh 2 ngày gần nhất)
- `PERF_REGRESSION_ALERT_ENABLED=true`
- `PERF_REGRESSION_P95_PCT=50`
- `PERF_REGRESSION_MIN_COUNT=50`

## 3) OPS API
- `GET /api/v1/ops/perf/reports/http?limit=14`
- `GET /api/v1/ops/perf/reports/http/:date`
- `GET /api/v1/ops/perf/reports/http/:date.xlsx`
