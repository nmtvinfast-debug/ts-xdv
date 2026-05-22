# V8 – Auto Outbox Hooks

## Mục tiêu
- Khi workflow phát sinh event (đã hook push), hệ thống tự **enqueue outbox** (EMAIL/SMS/ZALO) theo Template Engine.
- Không cần gọi thủ công `/internal/outbox/enqueue` nữa (vẫn giữ để test/debug).

## Cơ chế lấy contact khách hàng
1) Ưu tiên đọc từ DB theo ENV:
- CUSTOMER_TABLE (mặc định `customers`)
- CUSTOMER_PHONE_COL (`phone`)
- CUSTOMER_EMAIL_COL (`email`)
- CUSTOMER_ZALO_COL (`zalo_id`)

2) Nếu DB không có/không đúng: fallback từ `payload.meta`:
- meta.customerPhone / meta.customerEmail / meta.customerZaloId

## Kênh mặc định
- OUTBOX_DEFAULT_CHANNELS=ZALO,SMS,EMAIL
- Hệ thống chỉ enqueue kênh nào **có recipient hợp lệ**.

## Đã nối auto-outbox tại các điểm:
- Repair Orders: assign-job, transition -> chờ quyết toán (email kế toán)
- Inventory: phụ tùng về (email KTV fallback)
- Settlements: thanh toán xong (email CVDV + gửi cho khách nếu tìm thấy customer_id)
- Cars: xe vào xưởng (email Giám đốc + CVDV nếu có email)

> Nếu anh muốn auto-outbox cho **mọi transition** (khách đồng ý/không đồng ý, chờ thanh toán, ra xưởng...) thì em build tiếp v9 (mapping đầy đủ giống push).
