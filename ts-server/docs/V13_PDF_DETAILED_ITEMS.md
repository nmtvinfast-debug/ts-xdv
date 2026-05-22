# V13 – PDF chi tiết từ ro_items/parts_items

## Điểm chính
- PDF Engine giờ **tự đọc bảng công việc + phụ tùng** theo schema hiện có (best-effort).
- Không fix cứng tên bảng: service sẽ dò các bảng phổ biến:
  - Labor: ro_labor_items / repair_order_labor_items / ro_jobs / repair_order_jobs / ro_items / repair_order_items
  - Parts: ro_part_items / repair_order_part_items / ro_parts / repair_order_parts / parts_items / ro_items / repair_order_items
- Tự dò cột:
  - labor: hours, unit_price, amount, name...
  - parts: qty, unit_price, amount, code, name...
- Tính tổng:
  - Tiền công: lấy amount nếu có, không thì hours * LABOR_HOUR_RATE (mặc định 250.000)
  - VAT: lấy `repair_orders.vat_rate` nếu có, không thì 0
  - Giảm giá: lấy `discount_amount` hoặc `discount_percent` nếu có, không thì 0

## ENV
- `LABOR_HOUR_RATE=250000`

## Template
- RO_PDF được nâng lên **version=2 (PUBLISHED)**, dùng các trường:
  - laborItems[].{stt,name,hoursText,unitPriceText,amountText}
  - partItems[].{stt,code,name,qtyText,unitPriceText,amountText}
  - totals.*Text

Migration:
- `src/db/migrations/20260225111000_v13_pdf_templates_v2_publish.sql`
