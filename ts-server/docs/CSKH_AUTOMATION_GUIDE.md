# Phase 9F - CSKH Automation (thật)

## 1) Nguyên lý
- Rule lưu ở `cskh_automation_rules` (Phase 9D)
- Tác vụ chạy bởi queue job: `automation_tick`
- Khi match điều kiện -> tạo `cskh_events` (idempotent) -> tạo `outbound_messages` -> job `send` gửi thực

## 2) Chạy thủ công
`POST /api/v1/cskh/automation/run-now`

## 3) Chạy tự động định kỳ
Khuyến nghị Fly.io worker chạy cron:
- Mỗi 5 phút: enqueue `automation_tick` (hoặc chạy script cron gọi API)

Cách đơn giản: tạo cron ngoài (UptimeRobot/Grafana/cron server) gọi endpoint run-now (đã auth).

## 4) Template vars gợi ý
- `customer_name`, `bien_so`, `appt_time`
- `ro_id`, `feedback_link`

## 5) Feedback
- Public endpoint: `POST /api/v1/public/feedback`
- Lưu rating (1..5) và NPS (0..10)
