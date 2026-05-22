# Release Notes - Phase 12F.11 (HTTP metrics persist + export + alert)
Ngày: 2026-02-23

- Persist HTTP metrics to Redis (load on boot, save every 60s)
- Export HTTP metrics to Excel: GET /api/v1/ops/perf/http-metrics.xlsx
- Hot route alert job -> notifications (admin_tong/admin_global)
