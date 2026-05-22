# V22 – Accounting daily reconcile + reporting

## Endpoints
Base: `/api/reports/accounting`

1) Daily reconcile
- `GET /daily?date=YYYY-MM-DD&branch_id=<optional>`
Trả về:
- `settlement_summary` (count, customer_pay, insurance_pay, debt_amount)
- `receipt_summary`
- `voucher_summary`
- `method_breakdown` (cash/transfer/card/other từ settlement_lines)
- `open_debts_top`

2) Drilldown settlements list
- `GET /settlements?date=YYYY-MM-DD&branch_id=<optional>`
Danh sách các RO đã quyết toán trong ngày (kèm invoice/receipt status)

3) Shift report (theo khung giờ)
- `GET /shift?date=YYYY-MM-DD&shift=morning|afternoon|night`
Morning: 06-14, Afternoon: 14-22, Night: 22-06 (ngày hôm sau)

## Permissions
- Dùng `Permissions.DASHBOARD` (giám đốc/kế toán có quyền xem dashboard sẽ xem được báo cáo).

## DB Views
Migration:
- `20260225170000_v22_accounting_reporting_views.sql`
Views:
- `v_daily_settlement_summary`
- `v_daily_receipt_summary`
- `v_daily_voucher_summary`
