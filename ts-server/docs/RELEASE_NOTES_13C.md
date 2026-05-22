# Release Notes - Phase 13C (Master Data + Export Audit)
Ngày: 2026-02-23

## Added
- Master Data Center (per workshop): master_data_items
  - CRUD + export XLSX + template XLSX + import XLSX
  - Director routes: /api/v1/director/masterdata*
- Export audit logs: export_audit_logs
  - Middleware tự động ghi log khi trả file .xlsx/.pdf thành công

## Notes
- Master data dùng 1 bảng linh hoạt theo (type, code), dễ mở rộng.
