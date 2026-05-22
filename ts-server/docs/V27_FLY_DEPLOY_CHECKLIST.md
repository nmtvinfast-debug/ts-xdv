# V27 – Checklist deploy TS-Server lên Fly.io (production)

## 1) Chuẩn bị
- Fly app: `fly launch` (region gần VN/SG)
- Fly Postgres: `fly postgres create` + attach vào app
- Thiết lập secrets (bắt buộc):
  - `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`
  - `PUBLIC_BASE_URL` (vd: https://<app>.fly.dev)
  - `DATABASE_URL` (Fly set khi attach)
  - `S3_ENDPOINT/S3_BUCKET/S3_ACCESS_KEY/S3_SECRET_KEY` (nếu dùng S3)
  - `FCM_SERVICE_ACCOUNT_JSON` (nếu dùng push)
  - `EINVOICE_PROVIDER=stub` (hoặc provider thật)

## 2) Deploy flow
- `fly deploy`
- chạy migrate (release command hoặc manual):
  - `fly ssh console -C "node src/db/migrate.js"`
- seed RBAC + admin:
  - `fly ssh console -C "node src/db/seed.js"`
- seed demo (tuỳ chọn):
  - `fly ssh console -C "node src/db/seed_demo.js"`

## 3) Healthcheck & monitoring
- endpoint health: `/api/health` (nếu có) hoặc dùng script `npm run healthcheck`
- logs: `fly logs`
- scale:
  - web: 1-2 instances
  - workers: dùng `fly scale count` hoặc tách process group (khuyến nghị)

## 4) Worker jobs khuyến nghị bật
- outbox: `npm run worker:outbox`
- push: `npm run worker:push`
- retention: `npm run worker:retention`
- analytics/ai/tokens (tuỳ phase)

## 5) Các lỗi hay gặp
- Quên set `PUBLIC_BASE_URL` -> signed link sai
- Quên migrate -> thiếu bảng
- Fly Postgres connection limit -> tăng plan hoặc pool settings
