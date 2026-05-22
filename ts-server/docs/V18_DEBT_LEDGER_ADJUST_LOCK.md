# V18 – Debt ledger pay/adjust + fixes

## Fix bug
- Sửa lỗi insert `debt_payments` bị sai tham số (branch_id/debt_id) trong `src/modules/debts.js`.

## Ledger
- Khi thanh toán công nợ `POST /debts/:id/pay`:
  - ghi thêm `debt_ledger` action=`pay`.

## Điều chỉnh công nợ
- `POST /debts/:id/adjust`
  - body: `{ "delta": 100000, "note": "..." }`
  - delta âm để giảm nợ.
  - tự cập nhật lại `status` theo tổng đã trả.

## Xem sổ cái
- `GET /debts/:id/ledger`
