# Branch-safe Checklist (Phase 7B Complete)

## Rule
- Mọi danh sách/báo cáo thuộc nghiệp vụ vận hành có dữ liệu theo chi nhánh **phải lọc** theo `req.branch_id`:
  - Nếu `req.branch_id` = null: xem toàn xưởng.
  - Nếu có: chỉ xem dữ liệu của chi nhánh đó.
- Giám đốc/Admin có thể chọn chi nhánh qua header: `x-branch-id`.

## Covered tables
- repair_orders.branch_id
- appointments.branch_id
- inventory_moves.branch_id
- part_shortage_requests.branch_id
- debts.branch_id
- debt_payments.branch_id

## Covered modules
- Repair Orders: list + export + detail shortage list
- Appointments: list + export + CRM schedule appointment
- Inventory: moves list + export + create move + shortage create
- Shortages: list + export
- Debts: list + create + payments + join paid_amount (branch scoped)
- Settlements: pending list (branch scoped)
- Dashboard: stats + all lists + branch-summary + export
- Reports: revenue/debt-aging/stock-ledger/inout-summary/stocktake/cashbook/meeting-pack + overview counts (branch scoped)

## Quick tests
1. Create 2 branches A/B.
2. Create RO in A, RO in B.
3. Login user branch A -> list RO only A.
4. Director with x-branch-id=B -> list RO only B.
5. Export xlsx for each list -> must match the filtered items.
