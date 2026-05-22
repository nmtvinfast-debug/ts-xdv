# V7 – Monitoring + Retention + Outbox Providers

## Monitoring
- Request log (pino) + requestId
- Metrics Prometheus: `GET /metrics`
- Health: `GET /health`, `GET /ready`

## Retention ảnh/file
- Job: `npm run worker:retention`
- Dọn record `media_files` quá hạn `IMAGE_RETENTION_DAYS` (mặc định 10 ngày)
- Xóa file tại `UPLOADS_DIR` (mặc định `uploads/`)

> Lưu ý: Khi anh lưu ảnh checkin/đính kèm, cần insert record vào `media_files` để job dọn được.

## Outbox Providers
- Worker: `npm run worker:outbox`
- Bảng: `message_outbox`
- Internal enqueue:
  - `POST /internal/outbox/enqueue`
  - header `x-internal-key: INTERNAL_API_KEY`
- Provider:
  - EMAIL: SMTP (nodemailer) hoặc NOOP
  - SMS/ZALO: Webhook (anh tự nối nhà cung cấp) hoặc NOOP
- Retry: exponential backoff + giới hạn `max_attempts`

## Gợi ý nối Outbox vào hệ thống
- Khi tạo notification template EMAIL/SMS/ZALO → enqueueOutbox theo eventCode/payloadJson
- Khi workflow đổi trạng thái RO → enqueueOutbox cho khách hoặc nội bộ theo rule
