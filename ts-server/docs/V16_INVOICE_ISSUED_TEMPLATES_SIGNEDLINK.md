# V16 – INVOICE_ISSUED templates + signed link merge

## 1) Templates seed
Migration:
- `src/db/migrations/20260225124000_v16_seed_invoice_issued_templates.sql`
Tạo template GLOBAL cho event:
- `INVOICE_ISSUED` trên các channel: EMAIL / SMS / ZALO / PUSH

Các biến dùng:
- `meta.invoice_no`
- `meta.invoice_pdf_signed_url`
- `totals.grandTotalText`
- `vehicle.plate`, `ro.code`, `workshop.name`, `customer.name`

## 2) Merge signed link vào payload (accounting finalize hook)
Trong `POST /settlements/:roId` sau khi issue invoice:
- set `payload.meta.invoice_pdf_signed_url = <PUBLIC_BASE_URL>/api/media/<pdf_media_id>/signed?ttl=<INVOICE_PDF_SIGNED_TTL>`

ENV:
- `PUBLIC_BASE_URL` (khuyến nghị set để link đầy đủ)
- `INVOICE_PDF_SIGNED_TTL=600`
