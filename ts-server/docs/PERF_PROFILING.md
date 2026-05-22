# Profiling runtime + HTTP metrics + Index suggestions (12F.10)

## HTTP metrics (in-memory)
Middleware ghi nhận:
- count, errors_5xx
- avg/p50/p95/p99 (ms)
- avg/p95 payload size (KB)

OPS API:
- GET `/api/v1/ops/perf/http-metrics`
- POST `/api/v1/ops/perf/http-metrics/reset`

ENV:
- `PERF_HTTP_MAX_SAMPLES=500`

## Index suggestions (KHÔNG auto apply)
- GET `/api/v1/ops/perf/index-suggestions`
Heuristic:
- pg_stat_user_tables: seq_scan cao, idx_scan thấp, dữ liệu lớn -> cảnh báo table scan
- pg_stat_statements (nếu bật): parse pattern đơn giản để gợi ý index cho cột lọc "="

## Tool
- `npm run perf:http-metrics`
