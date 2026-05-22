# Phase 14B – Push Provider thật (FCM) + Tracking + Template Engine

## Mục tiêu
- Gửi push thật qua Firebase Cloud Messaging (FCM) cho **User** và **Customer**
- Có hàng đợi (queue) chống mất push
- Tracking đầy đủ: queued → sent/failed → opened
- Nội dung push **render qua Template Engine** (Phase 13D) nếu bật; nếu không có sẽ fallback.

## Cấu hình ENV
- `PUSH_PROVIDER=FCM`
- `FCM_PROJECT_ID=...`
- `FCM_CLIENT_EMAIL=...`
- `FCM_PRIVATE_KEY=...` (chuỗi có thể chứa \n)
- `TEMPLATE_ENGINE_URL=http://localhost:3000/internal/template/render` (nếu chạy chung server thì gọi nội bộ)
- `PUSH_WORKER_CRON=*/1 * * * *` (mặc định 1 phút chạy 1 lần)

## Luồng gửi
1. Khi hệ thống tạo thông báo cần push:
   - Insert record vào `push_events` với status = `QUEUED`
2. Worker `src/workers/push_worker.js` chạy theo cron:
   - Lấy batch `QUEUED` (lock bằng UPDATE ... WHERE status='QUEUED')
   - Resolve device tokens
   - Render template (nếu cấu hình Template Engine)
   - Gửi FCM
   - Update `push_events`: status, provider_message_id, sent_at/error

## Tracking opened
- Mobile app khi người dùng mở push → gọi API:
  - `POST /api/push/opened` `{ pushEventId }`
- Server update `opened_at` và status `OPENED`.

## Lưu ý bảo mật
- Endpoint opened yêu cầu JWT (user hoặc customer) và chỉ được đánh dấu opened cho bản ghi thuộc chính user/customer.


## Workflow hooks (auto enqueue)
- Đã nối enqueue push trực tiếp tại:
  - Repair Orders: assign-job, transition -> cho_quyet_toan
  - Inventory: receive-shortage (phụ tùng về)
  - Settlements: thanh toán xong
