# V28 – Worker schedules + cron locks (Postgres advisory lock)

## Mục tiêu
- Tự chạy định kỳ:
  - outbox dispatch
  - retry e-invoice
  - retention cleanup
- Chống chạy trùng khi scale nhiều instance (advisory lock)

## Components
- `src/services/cronLockService.js`
- `src/workers/scheduler.js`

## ENV
- `SCHED_OUTBOX_MS=5000`
- `SCHED_EINVOICE_MS=60000`
- `SCHED_RETENTION_MS=21600000` (6h)
- `OUTBOX_DISPATCH_LIMIT=200`
- `EINVOICE_RETRY_LIMIT=50`
- `RETENTION_WORKSHOP_ID=` (optional)

## Run
- `npm run worker:scheduler`
