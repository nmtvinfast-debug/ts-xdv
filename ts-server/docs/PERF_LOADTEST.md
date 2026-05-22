# Performance + Load Test + Query Diagnostics (12F.9)

## Load test
- k6: `tools/loadtest/k6/ro_workflow_smoke.js`
- artillery: `tools/loadtest/artillery/ro_workflow_smoke.yml`

## Ops perf endpoints (OPS_TOKEN)
- GET `/api/v1/ops/perf/pg_stat_statements`
- GET `/api/v1/ops/perf/slow-queries?limit=20`
- POST `/api/v1/ops/perf/explain`
- GET `/api/v1/ops/perf/index-health`

## Scripts
- `npm run perf:doctor`
- `npm run perf:pgstat`
