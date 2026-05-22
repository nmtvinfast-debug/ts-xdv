# Phase 9J - ISO Audit Pack

## 1) Trace ID
- Mỗi request được gán `trace_id`
- Response luôn trả header: `x-trace-id`
- Có thể gửi header `x-trace-id` từ client để xuyên suốt nhiều service

## 2) Audit Log
Bảng: `audit_logs`
Lưu:
- ai làm (user/role)
- làm gì (action)
- entity gì (entity_type/entity_id)
- trước/sau (before_json/after_json)
- trace_id, ip, user_agent, status_code, lỗi

## 3) API xem log + export
- `GET /api/v1/audit/logs?...`
- `GET /api/v1/audit/logs/export.xlsx?...`
- `GET /api/v1/audit/trace/:trace_id` (drilldown theo trace)

## 4) Best practice vận hành nội bộ
- Họp tuần: export audit theo action/role để kiểm soát sai quy trình
- Khi có lỗi: lấy `x-trace-id` từ client → drilldown toàn bộ thao tác trong phiên
