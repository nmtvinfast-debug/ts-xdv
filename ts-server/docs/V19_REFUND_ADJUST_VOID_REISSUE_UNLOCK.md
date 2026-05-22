# V19 – Refund/Adjust invoice + Reverse receipt + Unlock RO rules

## 1) Hủy / phát hành lại hóa đơn
API (settlements module):
- `POST /settlements/:roId/invoice/void`  body: `{ "reason": "..." }`
- `POST /settlements/:roId/invoice/reissue` body: `{ "reason": "..." }`

Quy tắc:
- Chỉ reissue khi hóa đơn đã `voided`.
- Reissue sẽ cấp số mới (tăng sequence) và regenerate PDF.

## 2) Hủy / phát hành lại phiếu thu (reverse)
- `POST /settlements/:roId/receipt/void` body: `{ "reason": "..." }`
- `POST /settlements/:roId/receipt/reissue` body: `{ "reason": "..." }`

## 3) Mở khóa RO theo quy tắc kế toán
- `POST /repair-orders/:id/unlock` body: `{ "reason": "..." }`

Rule:
- Chỉ unlock nếu không còn hóa đơn/phiếu thu đang hiệu lực (`status='issued'`).
- Nếu còn hiệu lực -> phải void chứng từ trước.

## 4) Audit
- `accounting_adjustments` lưu log các hành động: void/reissue/unlock.
- invoices/receipts thêm `voided_at/by/reason`.

## 5) Outbox templates (PUSH)
Seed:
- `INVOICE_VOIDED` (PUSH)
- `RECEIPT_VOIDED` (PUSH)
- `RO_UNLOCKED` (PUSH)

Events bắn best-effort:
- Khi void invoice -> `INVOICE_VOIDED`
- Khi void receipt -> `RECEIPT_VOIDED`
- Khi unlock RO -> `RO_UNLOCKED`
