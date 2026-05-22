# V31 – Fly.io Runbook (process groups + release migrate)

## 1) Process groups
- `web`: chạy API server
- `scheduler`: chạy worker scheduler (outbox/einvoice/retention)

Trong `fly.toml`:
- `[processes] web=...` và `scheduler=...`
- `http_service.processes=["web"]` để chỉ web nhận traffic

## 2) Release command (migrate)
Trong `fly.toml`:
- `[deploy] release_command="node src/db/migrate.js"`
=> mỗi lần deploy sẽ migrate trước khi app nhận traffic.

## 3) Deploy chuẩn
1) `fly launch` (hoặc sửa `fly.toml`)
2) Tạo/attach Fly Postgres
3) Set secrets:
   - `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`
   - `PUBLIC_BASE_URL`
   - `FCM_SERVICE_ACCOUNT_JSON` (nếu dùng push)
   - `S3_*` (nếu dùng storage)
4) `npm run fly:deploy`
5) Seed RBAC/admin:
   - `npm run fly:seed`
6) Seed demo (tuỳ chọn):
   - `npm run fly:seed:demo`

## 4) Scale & start process groups
- Scale web:
  - `fly scale count 1 --process web`
- Scale scheduler (khuyến nghị 1 instance):
  - `fly scale count 1 --process scheduler`

## 5) Healthcheck / Logs
- Logs: `npm run fly:logs`
- API docs:
  - `/api/docs/openapi.yaml`
  - `/api/docs/postman.json`

## 6) Rollback nhanh
- `fly releases`
- `fly rollback -i <release_id>`
