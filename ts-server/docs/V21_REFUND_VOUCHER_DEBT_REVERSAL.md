# V21 – Refund settlement + payment voucher PDF + debt reversal ledger

## 1) DB
Migrations:
- `20260225152000_v21_refund_payment_voucher.sql`
  - `payment_voucher_sequences`, `payment_vouchers`
  - `refunds`
- `20260225153000_v21_seed_payment_voucher_templates.sql`
  - `PAYMENT_VOUCHER_PDF` (PDF_HTML)
  - `REFUND_ISSUED` (EMAIL/SMS/ZALO/PUSH)

## 2) Refund API
- `POST /settlements/:roId/refund`
Body:
```json
{
  "amount": 200000,
  "method": "cash",
  "receiver_name": "Nguyễn Văn A",
  "reason": "Hoàn phần chênh lệch",
  "debtor_type": "customer",
  "debtor_name": "Nguyễn Văn A"
}
```

Rule:
- Bắt buộc đã có settlement (đã quyết toán)
- Tạo `payment_vouchers` + `refunds`
- Debt reversal:
  - Nếu đã có `debts` -> tăng `debts.amount` lên +amount và ghi `debt_ledger action=adjust`
  - Nếu chưa có -> tạo `debts open` và ghi `debt_ledger action=create`

## 3) PDF
- Service: `src/services/paymentVoucherService.js`
- PDF template: `PAYMENT_VOUCHER_PDF`
- Payload merge: `pdfService` sẽ tự đính kèm `paymentVoucher` (latest) cho RO

## 4) Outbox
- Event: `REFUND_ISSUED`
- Signed link:
  - `meta.voucher_pdf_signed_url = <PUBLIC_BASE_URL>/api/media/<mediaId>/signed?ttl=<VOUCHER_PDF_SIGNED_TTL>`

ENV:
- `PAYMENT_VOUCHER_PREFIX=PC`
- `PAYMENT_VOUCHER_SEQ_WIDTH=6`
- `VOUCHER_PDF_SIGNED_TTL=600`
