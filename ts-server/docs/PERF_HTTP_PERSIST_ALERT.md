# Perf HTTP Metrics Persist (Redis) + Export Excel + Hot Route Alert (12F.11)

## 1) Persist HTTP metrics vào Redis
ENV:
- PERF_HTTP_PERSIST_REDIS=true
- PERF_HTTP_REDIS_KEY=ts:perf:http_metrics:v1
- PERF_HTTP_PERSIST_INTERVAL_MS=60000

Cơ chế:
- Lúc boot: load snapshot từ Redis -> merge vào in-memory store
- Mỗi 60s: save in-memory store -> Redis
- Metrics vẫn chạy in-memory để nhanh; Redis để không mất khi restart

## 2) Export Excel
OPS API (OPS_TOKEN):
- GET `/api/v1/ops/perf/http-metrics.xlsx`

## 3) Hot Route Alert
ENV:
- PERF_HOT_ROUTE_ALERT_ENABLED=true
- PERF_HOT_ROUTE_ALERT_INTERVAL_MS=300000
- PERF_HOT_ROUTE_P95_MS=1500
- PERF_HOT_ROUTE_MIN_COUNT=30

Nếu route có p95 >= threshold và count >= minCount:
- tạo notification role=admin_tong và admin_global (severity=warning)
