# Phase 8L - SLA Escalation (Cảnh báo tự động)

## Rule mặc định (auto tạo)
- `cho_kh_dong_y_overdue`: 240 phút
- `cho_phu_tung_overdue`: 480 phút
- `dung_sua_overdue`: 180 phút
- `draft_overdue`: 360 phút

## Cơ chế
- Mỗi 5 phút hệ thống quét RO theo trạng thái và `last_status_changed_at`.
- Nếu quá ngưỡng:
  - tạo `alerts` (chống trùng theo dedupe_key = `sla:<rule_key>:<ro_id>`)
  - gửi `notifications` cho các role trong `sla_rules.notify_roles`.

## Cấu hình SLA
- Dùng API `PUT /api/v1/ops/sla-rules/:rule_key`
