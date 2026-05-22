# Chạy worker (Phase 14B Push)

## 1) Cài dependency
npm install

## 2) Chạy API server
npm run start

## 3) Chạy push worker
npm run worker:push

## ENV tối thiểu
- DATABASE_URL=...
- FCM_PROJECT_ID=...
- FCM_CLIENT_EMAIL=...
- FCM_PRIVATE_KEY=... (có thể chứa \n)
- TEMPLATE_ENGINE_URL=... (tùy chọn, nếu có Template Engine)

## Internal enqueue push (dành cho workflow)
- Endpoint: POST /internal/push/enqueue
- Header: x-internal-key = INTERNAL_API_KEY
- Body ví dụ:
  {
    "workshopId": "...",
    "userId": "...",
    "title": "Thông báo từ xưởng",
    "body": "Bạn có cập nhật mới",
    "eventCode": "JOB_ASSIGNED_TO_TECH",
    "payloadJson": { "ro": { "code": "RO-0001" }, "vehicle": { "plate": "20A-12345" } }
  }

## Token lifecycle cleanup
npm run worker:tokens

## Outbox worker (EMAIL/SMS/ZALO)
- Chạy: npm run worker:outbox
- Enqueue nội bộ: POST /internal/outbox/enqueue (x-internal-key = INTERNAL_API_KEY)

## Retention job (ảnh/file)
- Chạy: npm run worker:retention
- Mặc định dọn ảnh quá 10 ngày (IMAGE_RETENTION_DAYS=10)
