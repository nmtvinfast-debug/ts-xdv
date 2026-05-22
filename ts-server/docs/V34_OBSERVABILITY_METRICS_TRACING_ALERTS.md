# V34 – Observability pack (metrics + trace_id + health)

## 1) Trace ID + request metrics
Middleware:
- `src/middleware/requestMetrics.js`
Tự động:
- gắn `x-trace-id` cho mọi response
- metrics:
  - `http_requests_total{method,route,status}`
  - `http_request_duration_seconds` (histogram)

## 2) Prometheus metrics endpoint
Router:
- `src/modules/observability.js`

Endpoints:
- `GET /api/observability/metrics`
  - trả Prometheus text format
  - nếu set `METRICS_TOKEN` => yêu cầu header `x-metrics-token`
- `GET /api/observability/health`
  - trả JSON health + DB ping
- `POST /api/observability/metrics/gauges`
  - worker push gauge (requires `METRICS_TOKEN`)

## 3) Worker scheduler push gauges
- `src/workers/scheduler.js` push:
  - `scheduler_last_run_seconds{job="outbox|einvoice|retention"}`

## 4) Gợi ý alert rules (log-based/metrics-based)
- Tăng `http_requests_total{status="500"}` đột biến
- `scheduler_last_run_seconds{job="outbox"}` không cập nhật > 60s
- `scheduler_last_run_seconds{job="einvoice"}` không cập nhật > 10m
- Health endpoint trả 503

## 5) Fly.io setup gợi ý
- Dùng Grafana/Prometheus external scrape:
  - scrape `/api/observability/metrics` kèm header token
- Hoặc dùng log-based alert nếu chưa có Prometheus.
