# V20 – RO lock enforcement guardrails

## Mục tiêu
- Chặn mọi thao tác **sửa dữ liệu RO** khi RO đã bị khóa (`repair_orders.is_locked=true`), nhằm đảm bảo tính đúng đắn kế toán sau quyết toán.

## Cơ chế
- Service mới: `src/services/roLockService.js`
  - `assertRoUnlocked({ workshopId, roId })` -> throw 409 `RO_LOCKED` nếu bị khóa.

## Áp dụng
Đã cấy guard `await assertRoUnlocked(...)` vào các endpoint mutating phổ biến:
- `src/modules/repair_orders_routes.js`
  - cập nhật RO / thêm sửa item / thêm sửa phụ tùng / cập nhật vị trí… (tùy endpoint có trong bản code)
- `src/modules/repair_orders.js`
  - start/stop/resume/complete (workflow tác vụ có thể làm thay đổi dữ liệu)
- `src/modules/packages.js`
  - apply package vào RO (nếu có endpoint)

## Message lỗi (VI)
- `RO đã khóa sau quyết toán. Hãy hủy chứng từ và mở khóa RO trước khi chỉnh sửa.`
