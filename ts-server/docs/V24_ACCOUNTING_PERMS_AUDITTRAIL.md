# V24 – Accounting perms tách riêng + Audit trail (IP/UA)

## 1) Permissions
Thêm permissions:
- `accounting:finalize`
- `accounting:void`
- `accounting:unlock`
- `accounting:refund`

Fix thiếu permission constants:
- `reports:view`, `reports:export`, `lsc:manage` (để không crash do reference cũ)

Role mapping:
- `KE_TOAN`: được cấp `accounting:*` + reports view/export (ngoài SETTLEMENT legacy)
- `GIAM_DOC`: được cấp reports view/export

## 2) Audit log
DB:
- `audit_events`

Service:
- `src/services/auditService.js`
  - log kèm IP + User-Agent + path + method + request/response

Ghi audit cho các action quan trọng:
- finalize settlement
- void invoice/receipt
- pay debt
- unlock RO

## 3) Audit report API
- `GET /api/reports/audit?from=YYYY-MM-DD&to=YYYY-MM-DD&action=&limit=200`
Permission:
- `reports:view`
