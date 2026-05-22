# V26 – Data retention & storage cleanup jobs

## 1) DB
Migrations:
- `20260225190000_v26_retention_policies_cleanup_runs.sql`
  - `retention_policies` (GLOBAL hoặc theo workshop)
  - `cleanup_runs` (log chạy job)
- `20260225191000_v26_seed_retention_defaults.sql`

Defaults (GLOBAL):
- `vehicle_checkin_photos_days = 10`
- `ro_attachments_days = 90`
- `pdf_*_days = 3650` (để dành cho phase sau nếu muốn cleanup PDF)
- `audit_events_days = 365`

## 2) Service
- `src/services/retentionService.js`
Job:
- xóa media kind `VEHICLE_CHECKIN_PHOTO` sau X ngày (mặc định 10)
- xóa media kind `RO_ATTACHMENT` sau Y ngày (mặc định 90)
- xóa audit_events cũ sau Z ngày (mặc định 365)

> Xóa media dùng `storageDelete()` (best-effort) + đánh dấu `media.deleted_at`.

## 3) API manual trigger
- `POST /api/retention/run` (permission: `DASHBOARD`)

## 4) Ghi chú
- PDF chứng từ (invoice/receipt/voucher) mặc định giữ dài hạn; nếu muốn cleanup thêm sẽ build pack tiếp.
