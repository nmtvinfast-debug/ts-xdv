# V15 – Invoice numbering + Accounting finalize hooks

## 1) DB
Migration:
- `src/db/migrations/20260225121000_v15_invoice_numbering_tables.sql`
Tạo:
- `invoice_sequences`: lưu last_no theo (workshop, branch, year, prefix)
- `invoices`: lưu hóa đơn theo RO (unique per RO), có `invoice_no`, `pdf_media_id`

## 2) Số hóa đơn
Service:
- `src/services/invoiceService.js`
Format mặc định:
- Có branch code: `HD-<BR>-YYYY-000001`
- Không có branch: `HD-YYYY-000001`

ENV:
- `INVOICE_PREFIX=HD`
- `INVOICE_SEQ_WIDTH=6`
- `INVOICE_YEAR_OVERRIDE=` (tuỳ chọn)

## 3) Hook khi quyết toán (Kế toán)
- Endpoint: `POST /settlements/:roId`
Sau khi chuyển RO -> `da_thanh_toan` sẽ:
- `issueInvoiceIfMissing()`
- tự tạo PDF `INVOICE_PDF` (dùng v12-v14 PDF engine)
- enqueue outbox event `INVOICE_ISSUED` (nếu template có)

## 4) API xuất hóa đơn
- `POST /settlements/:roId/invoice`
  - đảm bảo đã quyết toán
  - phát hành số hóa đơn nếu chưa có
  - trả về `invoice_no` + `pdf_url` + signed endpoint
