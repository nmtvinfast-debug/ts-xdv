# V17 – Accounting closeout + debt tracking + receipt PDF

## 1) Closeout (Kế toán quyết toán)
Endpoint hiện có:
- `POST /settlements/:roId`

V17 bổ sung:
- Ghi `settlement_lines` (chi tiết các dòng thanh toán)
  - Nếu body có `payment_lines[]` thì dùng, nếu không fallback theo `customer_pay` + `insurance_pay`
- Nếu có công nợ (`debt_amount>0`):
  - tạo `debts` (open)
  - tạo `debt_ledger` action='create'
- Lock RO (best-effort):
  - set `repair_orders.is_locked=true`, `locked_at`, `locked_by` khi chuyển `da_thanh_toan`

Body mở rộng:
```json
{
  "customer_pay": 1000000,
  "insurance_pay": 0,
  "debt_amount": 500000,
  "debt_owner": "customer",
  "note": "Ghi chú",
  "payment_lines": [
    {"payer_type":"KH","method":"cash","amount":1000000,"note":""},
    {"payer_type":"BH","method":"transfer","amount":0,"note":""}
  ]
}
```

## 2) Phiếu thu
- Issue tự động sau khi quyết toán xong (v17)
- API:
  - `POST /settlements/:roId/receipt`

Số phiếu:
- `PT-<BR>-YYYY-000001` hoặc `PT-YYYY-000001`

ENV:
- `RECEIPT_PREFIX=PT`
- `RECEIPT_SEQ_WIDTH=6`
- `RECEIPT_PDF_SIGNED_TTL=600`

## 3) Template
Migration seed:
- `20260225133000_v17_seed_receipt_templates.sql`
  - `RECEIPT_PDF` (PDF_HTML)
  - `RECEIPT_ISSUED` (EMAIL/SMS/ZALO/PUSH)

## 4) Outbox event
Sau finalize:
- `INVOICE_ISSUED` (v16)
- `RECEIPT_ISSUED` (v17)
