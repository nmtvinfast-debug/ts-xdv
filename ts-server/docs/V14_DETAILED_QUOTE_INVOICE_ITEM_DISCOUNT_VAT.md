# V14 – Detailed Quote + Invoice + item discount/vat

## Điểm chính
- Extractor đọc được discount/vat theo dòng nếu DB có cột:
  - discount_amount / discount_percent
  - vat_rate
- Tổng:
  - subtotal = tổng base
  - giảm: itemDiscount + roDiscount (nếu có)
  - VAT: ưu tiên theo dòng; nếu dòng không có VAT và repair_orders có vat_rate thì tính theo document.
- Quote/Invoice template nâng lên v2 (PUBLISHED).

## Migration
- `src/db/migrations/20260225114000_v14_quote_invoice_pdf_v2_publish.sql`

## ENV
- `DEFAULT_VAT_RATE=0` (0..1)
