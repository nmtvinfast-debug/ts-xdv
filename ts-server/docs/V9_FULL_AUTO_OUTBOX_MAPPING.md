# V9 – Full Auto-Outbox Mapping

## Mục tiêu
- Auto enqueue outbox (EMAIL/SMS/ZALO) cho **tất cả trạng thái workflow RO** giống mapping PUSH.

## Đã nối trong
- `src/modules/repair_orders.js` – endpoint `POST /api/repair-orders/:id/transition`
  - cho_kh_dong_y:
    - KH: CUSTOMER_APPROVAL_REQUESTED
    - Nội bộ: RO_WAITING_CUSTOMER_APPROVAL (giamdoc/cvdv)
  - dang_sua:
    - KH: RO_STARTED
    - Nội bộ: CUSTOMER_APPROVED (quandoc)
  - khong_dong_y:
    - Nội bộ: CUSTOMER_REJECTED (cvdv/giamdoc)
  - dung_sua:
    - KH + nội bộ: RO_PAUSED (cvdv)
  - cho_phu_tung:
    - KH: RO_WAITING_PARTS
    - Nội bộ: PARTS_REQUESTED (kho/cvdv)
  - hoan_thanh_ky_thuat:
    - KH + nội bộ: RO_TECH_DONE (cvdv)
  - cho_quyet_toan:
    - KH: RO_WAITING_PAYMENT
    - Nội bộ: RO_MOVED_TO_ACCOUNTING (ketoan)
  - da_thanh_toan:
    - KH + nội bộ: PAYMENT_COMPLETED (baove)
  - ra_xuong:
    - KH + nội bộ: VEHICLE_CHECKOUT (giamdoc)

## Lưu ý contact KH
- Ưu tiên đọc từ bảng `customers` (config ENV), fallback `payload.meta`.
