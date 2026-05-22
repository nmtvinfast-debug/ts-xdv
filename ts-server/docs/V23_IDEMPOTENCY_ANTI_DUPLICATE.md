# V23 – Idempotency + chống bấm 2 lần

## 1) DB
Migration:
- `src/db/migrations/20260225160000_v23_idempotency_requests.sql`
Bảng:
- `idempotency_requests` unique theo `(workshop_id, op, idempotency_key)`

## 2) Header
Client gửi 1 trong 2 header:
- `Idempotency-Key: <uuid-or-random>`
- `X-Idempotency-Key: <uuid-or-random>`

## 3) Hành vi
- Nếu cùng key + cùng op + cùng request hash:
  - Lần 1: xử lý bình thường và lưu response
  - Lần sau: trả lại **đúng response** đã lưu
- Nếu cùng key nhưng body khác: trả **409**

## 4) Áp dụng
Đã áp dụng wrapper `runIdempotent()` cho các action dễ bấm lặp:
- `POST /settlements/:roId` => `SETTLEMENT_FINALIZE`
- `POST /settlements/:roId/invoice` => `INVOICE_ISSUE`
- `POST /settlements/:roId/invoice/void` => `INVOICE_VOID`
- `POST /settlements/:roId/invoice/reissue` => `INVOICE_REISSUE`
- `POST /settlements/:roId/receipt` => `RECEIPT_ISSUE`
- `POST /settlements/:roId/receipt/void` => `RECEIPT_VOID`
- `POST /settlements/:roId/receipt/reissue` => `RECEIPT_REISSUE`
- `POST /settlements/:roId/refund` => `REFUND_ISSUE`
- `POST /repair-orders/:id/unlock` => `RO_UNLOCK`
- `POST /debts/:id/pay` => `DEBT_PAY`

ENV:
- `IDEMPOTENCY_TTL=3600`
