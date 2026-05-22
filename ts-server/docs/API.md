# API (tóm tắt)

Base URL: `http://localhost:3000` hoặc Fly: `https://ts-server.fly.dev`

## Auth
- `GET /health`
- `POST /auth/bootstrap`
- `POST /auth/login`
- `GET /auth/me`

## Users (Giám đốc / Admin)
- `GET /users`
- `POST /users`
- `PATCH /users/:id`

## CSKH (Đặt hẹn)
- `GET /appointments`
- `POST /appointments`

## Bảo vệ
- `GET /cars?status=in_workshop`
- `POST /cars/checkin`
- `PATCH /cars/:id` (đổi trạng thái/vị trí, “test_drive” -> default position “Ngoài đường”)

## CVDV / RO
- `GET /repair-orders`
- `GET /repair-orders/:id`
- `POST /repair-orders`
- `POST /repair-orders/:id/jobs`
- `POST /repair-orders/:id/parts`
- `PATCH /repair-orders/:id/status`
- `PATCH /repair-orders/:id/customer-approval`
- `PATCH /repair-orders/:id/assign-job`

## Kho
- `GET /inventory/items`
- `POST /inventory/items`
- `POST /inventory/move`

## Kế toán
- `GET /settlements/queue`
- `POST /settlements/:ro_id`

## Dashboard
- `GET /dashboard/stats`
- `GET /dashboard/cars-in-workshop`
- `GET /dashboard/ro-by-status?status=...`

## Notifications
- `GET /notifications`
- `PATCH /notifications/:id/read`
- (admin) `POST /notifications/send`

## Gói dịch vụ
- `GET /packages`
- `POST /packages`
- `POST /packages/:id/apply/:ro_id`

## Compatibility (Flutter cũ)
- `GET /api/work-orders`
- `GET /api/work-orders/:id`
- `PATCH /api/work-orders/:id/status`
- `PATCH /api/work-orders/:id/assign`


## Công nợ (Debts)
- `GET /debts?status=&q=&page=&limit=`
- `GET /debts/:id`
- `POST /debts/:id/pay` (thanh toán từng phần)

## Giám đốc (alias)
- `GET /xdv/workshop`
- `PATCH /xdv/workshop`
- `GET /xdv/users` (alias của /users)
- `POST /xdv/users`


## Thông báo
- `GET /notifications` (list theo role/user)
- `PATCH /notifications/:id/read`
- `POST /notifications/send` (gửi thủ công)

## Mẫu thông báo
- `GET /notification-templates`
- `POST /notification-templates` (upsert theo event_key + target_role)
- `PATCH /notification-templates/disable`

- `GET /repair-orders/export`
- `GET /inventory/items/export`
- `GET /inventory/moves/export`
- `GET /debts/export`
- `GET /users/export`
- `GET /appointments/export`

## Xuất Excel cho các danh sách
Hầu hết các API dạng danh sách hỗ trợ `?export=xlsx` để tải file Excel phục vụ họp.
Ví dụ:
- `GET /users?export=xlsx`
- `GET /repair-orders?status=dang_sua&export=xlsx`
- `GET /inventory/items?q=lop&export=xlsx`
- `GET /inventory/moves?move_type=out&export=xlsx`
- `GET /debts?status=open&export=xlsx`
- `GET /settlements/pending?export=xlsx`
- `GET /appointments?export=xlsx`
- `GET /notifications?export=xlsx`


## Phụ tùng thiếu (Shortages)
- `GET /shortages?status=&q=&page=&limit=&export=xlsx`
- `PATCH /shortages/:id/status`


## Dashboard drill-down (Giám đốc)
- `GET /dashboard/director/stats`
- `GET /dashboard/director/list/:type?q=&page=&limit=&export=xlsx`


## KTV - Việc của tôi
- `GET /ktv/my-jobs?status=&q=&page=&limit=&export=xlsx`


## Export Excel bổ sung (phục vụ họp)
Các danh sách sau hỗ trợ `?export=xlsx`:
- `GET /cars?status=&q=&page=&limit=&export=xlsx`
- `GET /packages?q=&page=&limit=&export=xlsx`
- `GET /work-orders?status=&q=&page=&limit=&export=xlsx`
- `GET /audit?q=&from=&to=&page=&limit=&export=xlsx`
- `GET /notification-templates?export=xlsx`
- `GET /workshops?export=xlsx` (admin_tong)


## Xuất quyết toán theo RO
- `GET /settlements/:roId/export` (Excel 3 sheet: Tổng hợp / Công việc / Phụ tùng)


## Báo cáo (Reports)
- `GET /reports/ktv-kpi?from=&to=&export=xlsx`
- `GET /reports/ro-aging?status=&min_age=&export=xlsx`


## Cấu hình cảnh báo (Settings)
- `GET /settings/workshop`
- `PATCH /settings/workshop`

## Chạy cảnh báo tự động
- `POST /system/alerts/run` (gọi theo cron)

## Xuất chi tiết RO
- `GET /repair-orders/:id/export-detail` (Excel 4 sheet: Tổng hợp/Công việc/Phụ tùng/Timeline)

## Báo cáo lợi nhuận ước tính
- `GET /reports/ro-profit?from=&to=&q=&export=xlsx`


## Báo cáo doanh thu
- `GET /reports/revenue?from=&to=&group=day|month&export=xlsx`

## Báo cáo lợi nhuận theo RO (real)
- `GET /reports/ro-profit-real?from=&to=&q=&export=xlsx`


## Báo cáo lợi nhuận theo xuất kho
- `GET /reports/ro-profit-stock?from=&to=&q=&export=xlsx`


## Kho - Xuất kho hàng loạt theo RO
- `POST /inventory/issue-ro-parts`

## Kho - Kiểm kê/điều chỉnh tồn
- `POST /inventory/adjust`

## Báo cáo giá trị tồn kho
- `GET /reports/inventory-valuation?q=&export=xlsx`


## Kho - Sổ kho / Nhập-Xuất / Kiểm kê
- `GET /reports/stock-ledger?part_code=&from=&to=&export=xlsx`
- `GET /reports/inout-summary?from=&to=&group=day|month&export=xlsx`
- `GET /reports/stocktake?from=&to=&part_code=&export=xlsx`


## Kế toán - Sổ quỹ / Tuổi nợ / Xếp hạng
- `GET /reports/cashbook?from=&to=&export=xlsx`
- `GET /reports/debt-aging?as_of=&export=xlsx`
- `GET /reports/ranking-cvdv?from=&to=&export=xlsx`
- `GET /reports/ranking-ktv?from=&to=&export=xlsx`


## Gói báo cáo họp tuần
- `GET /reports/payment-method-summary?from=&to=&export=xlsx`
- `GET /reports/meeting-pack?from=&to=&export=xlsx`


## Realtime (nội bộ)
- `GET /events/stream` (SSE cho TV Dashboard)

## KPI + Anti-loss
- `GET /reports/kpi-summary`
- `GET /reports/anomalies?from=&to=&export=xlsx`


## Phase 6B - Onboarding / Billing / Export
### Onboarding (Admin tổng)
- `POST /admin/onboarding/bootstrap`
- `POST /admin/onboarding/seed-users`
- `GET /admin/onboarding/seed-template`

### Billing (thủ công / chuẩn bị tích hợp MoMo/Stripe)
- `POST /billing/invoices` (admin)
- `POST /billing/invoices/:id/mark-paid` (admin)
- `GET /billing/invoices` (xưởng)

### Export dữ liệu
- `GET /export/full?format=json` (download JSON)
- `GET /export/history`


## Phase 6C - Checkout + Webhook + Org/Branch + Backup job
### Billing (tạo link thanh toán)
- `POST /billing/checkout` body: `{ plan_code, months, provider: 'momo'|'stripe' }`
- `POST /billing/webhook/momo` (public)
- `POST /billing/webhook/stripe` (public, raw body)

### Organization / Branch
- `POST /orgs` (admin tổng)
- `GET /orgs` (admin tổng)
- `POST /orgs/:org_id/branches` (admin tổng)
- `PATCH /orgs/users/:user_id/branch` (giám đốc xưởng)

### Backup job
- ENV: `BACKUP_ENABLED=true`, `BACKUP_CRON="0 2 * * *"`, `BACKUP_DIR="./backups"`


## Phase 6D - Recurring Billing + S3/R2 Backup + SaaS Admin
### Billing recurring job
- ENV: `BILLING_ENABLED=true`, `BILLING_CRON="0 1 * * *"`, `BILLING_LEAD_DAYS=7`

### SaaS Admin
- `GET /admin/saas/overview`
- `GET /admin/saas/invoices?status=pending|paid|failed`

### Backup S3/R2 (tuỳ chọn)
- `BACKUP_STORAGE=s3`
- `S3_BUCKET=...`
- `S3_REGION=...`
- `S3_ENDPOINT=...` (R2/S3 compatible)
- `AWS_ACCESS_KEY_ID=...`, `AWS_SECRET_ACCESS_KEY=...`
- `S3_PUBLIC_BASE_URL=...` (nếu muốn link public)


## Phase 6E - Auto pay_url + Grace period + Hardening Vietnamese
### Billing paylink job
- ENV: `BILLING_PAYLINK_CRON="*/10 * * * *"`
- Khi invoice pending chưa có pay_url => job tự tạo pay_url (MoMo/Stripe) và gửi thông báo cho Giám đốc.

### Grace period
- `workshop_subscriptions.grace_days` (mặc định 7)
- Hết hạn + grace_days mới bị khóa API (trong thời gian grace vẫn cho dùng, có cờ `req.subscription.is_grace=true`).


## Phase 6F - Thông báo đa kênh + Escalation + Soft-lock/Hard-lock
### Admin cấu hình kênh thông báo
- `PATCH /admin/billing-ops/workshops/:id/contacts`
- `PATCH /admin/billing-ops/workshops/:id/policy`

### Outbound message queue
- Bảng: `outbound_messages`
- Job: bật `NOTIFY_ENABLED=true` để tự gửi (SMTP/HTTP/console)

### Billing notify escalation
- ENV: `BILLING_NOTIFY_CRON="0 */6 * * *"`

### Lock policy
- `grace_days` (mặc định 7): quá hạn vẫn dùng được
- `soft_lock_days` (mặc định 3): hết grace → CHỈ XEM (block mọi POST/PUT/PATCH/DELETE)
- Sau grace + soft_lock → khóa hoàn toàn (403)


## Phase 6G - Banner API + Template thông báo + SaaS report nâng cao
### System Banner
- `GET /system/banner` trả `lock_mode`, `message`, `pending_invoice.pay_url` để app hiển thị CTA thanh toán.

### Billing ops
- `POST /billing/ops/resend-paylink` (giám đốc): gửi lại link thanh toán qua email.

### SaaS Admin reports
- `GET /admin/saas/revenue-monthly?months=12`
- `GET /admin/saas/top-workshops?limit=20`
- `GET /admin/saas/churn-cohort`


## Phase 7A.1 - Tự động nhắc bảo dưỡng + gợi ý xin đánh giá
### CRM Reminder automation
- Job: bật `CRM_NOTIFY_ENABLED=true`
- ENV: `CRM_NOTIFY_CRON="0 8 * * *"`, `CRM_REMINDER_LEAD_DAYS=3`
- Gửi vào `outbound_messages` (ưu tiên email nội bộ của xưởng: `workshops.contact_email`)

### Feedback request automation
- Job: bật `CRM_FEEDBACK_ENABLED=true`
- ENV: `CRM_FEEDBACK_CRON="0 18 * * *"`, `CRM_FEEDBACK_LOOKBACK_DAYS=2`

### CRM APIs
- `GET /crm/reminders?status=pending|done`
- `PATCH /crm/reminders/:id/done`


## Phase 7A.2 - CSKH Dashboard + Call log + Auto tạo reminder sau khi đóng RO
### CRM Auto reminder từ RO
- Job: `CRM_AUTO_REMINDER_ENABLED=true`
- ENV: `CRM_AUTO_REMINDER_CRON="*/30 * * * *"`, `CRM_AUTO_REMINDER_LOOKBACK_HOURS=24`
- Rule: `POST /crm/rules` cấu hình mặc định `default_days` (vd 90 ngày) và `default_km`

### CSKH Dashboard & Call logs
- `GET /crm/dashboard-today` (pending <= hôm nay)
- `POST /crm/calls` (ghi nhận cuộc gọi)
- `GET /crm/calls` (list lịch sử gọi)


## Phase 7A.3 - Chốt lịch hẹn từ reminder + trạng thái reminder + export họp sáng
### Reminder flow
- `service_reminders.stage`: pending|called|scheduled|done|cancelled
- Tag nhanh: `service_reminders.tags`

### APIs
- `POST /crm/reminders/:id/schedule` -> tạo `appointments` (source=crm_reminder) + cập nhật reminder stage=scheduled
- `PATCH /crm/reminders/:id/stage` (stage + tags)
- `PATCH /crm/reminders/:id/cancel`
- Export họp: 
  - `GET /crm/dashboard-today?export=xlsx`
  - `GET /crm/reminders?export=xlsx`


## Phase 7B - Audit log + Chi nhánh + Security hardening + Health/Monitoring
### Branches (chi nhánh)
- `GET /branches` (Giám đốc/Admin)
- `POST /branches`
- `PATCH /branches/:id`
Header chọn chi nhánh (Giám đốc/Admin): `x-branch-id`

### Audit log
- `GET /audit?limit=500&ref_type=&ref_id=&export=xlsx`
Ghi tự động cho mọi request ghi (POST/PUT/PATCH/DELETE)

### Security
- Helmet bật mặc định
- Rate limit login: ENV `RATE_LIMIT_LOGIN_MAX` (mặc định 30/10 phút)
- Allowlist IP Admin tổng: `ADMIN_IP_ALLOWLIST="1.2.3.4,5.6.7.8"`

### Health
- `GET /system/health`
- `GET /system/health/outbound`


## Phase 7B.1 - Enforce lọc chi nhánh cho danh sách RO/Đặt hẹn/CRM chốt hẹn
- RO list + export: tự lọc theo `req.branch_id` (từ user.branch_id hoặc header `x-branch-id` với Giám đốc/Admin)
- Appointments list + export: lọc theo chi nhánh
- CRM schedule: khi tạo appointment từ reminder sẽ gán branch_id theo `req.branch_id`


## Phase 7B.2 - Enforce chi nhánh cho Kho + Công nợ + Báo cáo quan trọng
### DB
- `inventory_moves.branch_id`
- `part_shortage_requests.branch_id`
- `debts.branch_id`
- `debt_payments.branch_id`

### Enforce/filter
- Inventory moves export: lọc theo chi nhánh
- Debts list + create/payment: gán & lọc theo chi nhánh
- Reports: revenue / debt-aging / stock-ledger / inout-summary / stocktake / cashbook / meeting-pack lọc theo chi nhánh


## Phase 7B.3 - Enforce chi nhánh cho Shortages + Inventory moves list + Dashboard tổng hợp theo chi nhánh
- Shortages list/export: lọc theo `ps.branch_id`
- Inventory moves list: lọc theo `branch_id`
- Dashboard:
  - `/dashboard/stats` đã hỗ trợ lọc theo chi nhánh (theo `req.branch_id`)
  - `/dashboard/branch-summary` (Giám đốc/Admin) tổng hợp KPI theo từng chi nhánh + export xlsx


## Phase 7B.3b - Enforce chi nhánh cho Quyết toán + các list Dashboard
- Settlement pending list lọc theo chi nhánh
- Dashboard lists (cars-in-workshop / ro-waiting-assign / ro-paused / ro-waiting-settlement / parts-missing) lọc theo chi nhánh


## Phase 7B COMPLETE - Branch-safe toàn hệ thống (đóng gói chuẩn)
Xem thêm: `docs/BRANCH_SAFE_CHECKLIST.md`


## Phase 8A - State Machine RO (chuẩn TS) + Timeline + Log chuyển trạng thái
### Quy tắc
- Không cho cập nhật `status` trực tiếp bằng PATCH/PUT.
- Phải dùng API chuyển trạng thái.

### API
- `POST /api/v1/repair-orders/:id/transition`
  - body:
    - `to_status` (bắt buộc)
    - `note` (tuỳ chọn)
    - `pause_reason` (bắt buộc nếu `to_status=dung_sua`): `cho_kh|cho_phu_tung|bao_hiem|khac`
- `GET /api/v1/repair-orders/:id/transitions` (xem lịch sử chuyển trạng thái)

### DB
- Bảng `ro_transitions`
- Cột timeline trên `repair_orders`:
  - `xe_vao_xuong_at`, `bat_dau_sua_at`, `dung_sua_at`, `tiep_tuc_sua_at`, `hoan_thanh_ky_thuat_at`, `cho_quyet_toan_at`, `thanh_toan_at`, `xe_ra_xuong_at`


## Phase 8B - CSKH phân công CVDV khi xe vào xưởng (Intake)
### Quy tắc
- CSKH xem danh sách xe đang trong xưởng nhưng chưa có RO hoạt động hoặc RO chưa có CVDV.
- CSKH chọn CVDV -> hệ thống:
  - Nếu đã có RO hoạt động: gán `assigned_manager` = CVDV
  - Nếu chưa có: tạo RO `status='draft'`, gán `assigned_manager` = CVDV
  - Gửi thông báo tới CVDV

### API
- `GET /api/v1/cskh/intake/cvdv-options`
- `GET /api/v1/cskh/intake/incoming-cars`
- `POST /api/v1/cskh/intake/assign-cvdv`
  - body: `car_id|bien_so`, `cvdv_user_id`, `note?`


## Phase 8C - CVDV Import/Export LSC VinFast (lịch sử dịch vụ)
### DB
- `vinfast_lsc_records` (có chống trùng theo workshop + biển số/vin + ngày + hash nội dung)

### API
- `GET /api/v1/vinfast/lsc/template.xlsx` (tải mẫu import)
- `POST /api/v1/vinfast/lsc/import` (multipart form-data: `file`)
- `GET /api/v1/vinfast/lsc/records?bien_so=&vin=&from=&to=`
- `GET /api/v1/vinfast/lsc/export.xlsx?bien_so=&vin=&from=&to=`

### Quy ước import
- Bắt buộc: (Biển số hoặc VIN) + Ngày dịch vụ + Nội dung
- Chống trùng: cùng workshop + biển số/VIN + ngày + nội dung => bỏ qua dòng trùng


## Phase 8D - Timeline đầy đủ cho RO (mốc thời gian + truy vết)
### DB
- `repair_orders.cho_phu_tung_at`
- `repair_orders.last_status_changed_at`
- Timeline events ghi vào bảng `timelines` (event_type = `ro_status_<to_status>`)

### API
- `GET /api/v1/repair-orders/:id/timeline`
  - trả về `timelines[]` + `transitions[]` để UI render lịch sử & mốc thời gian


## Phase 8E - Admin tổng tạo XDV + Giám đốc quản lý tài khoản nội bộ
### Admin tổng (admin_tong/admin_global)
- `GET /api/v1/admin/workshops?q=`
- `POST /api/v1/admin/workshops`
  - body: `name`, `code?`, `address?`, `backend_url?`, `contact_phone?`, `contact_zalo?`, `contact_email?`
  - director: `director_username?`, `director_password?`, `director_full_name?`
  - Tự tạo: chi nhánh mặc định `MAIN` + tài khoản `giam_doc`
- `PATCH /api/v1/admin/workshops/:id`
- `POST /api/v1/admin/workshops/:id/reset_director_password` (body: `new_password`)

### Giám đốc XDV
- Dùng module User Management sẵn có:
  - `GET /api/v1/users`
  - `POST /api/v1/users` (tạo user + `branch_id` + `phone`)
  - `PUT /api/v1/users/:id` (sửa user + `branch_id` + `phone` + khoá/mở khoá)
  - `GET /api/v1/users/export`


## Phase 8F - Enforce Workflow theo role + trạng thái (RO)
### Nguyên tắc
- Từ Phase 8A: trạng thái RO chỉ đổi qua `POST /repair-orders/:id/transition`.
- Phase 8F: các thao tác sửa nội dung RO bị khoá theo trạng thái + vai trò.

### Quy định chính
- CVDV chỉ được thêm/sửa công việc & phụ tùng khi RO ở: `draft`, `cho_kh_dong_y`.
- Quản đốc chỉ được phân công KTV khi RO chưa kết thúc/huỷ.
- KTV chỉ được ghi worklog khi RO ở: `dang_sua`, `dung_sua`, `cho_phu_tung` và chỉ với job được phân công.

### Deprecated API
- `PATCH /repair-orders/:id/status` -> trả 400
- `PATCH /repair-orders/:id/customer-approval` -> trả 400


## Phase 8G - Danh sách chuẩn theo vai trò + drill-down + export để họp
### API
- `GET /api/v1/role-lists/:list_key`
- `GET /api/v1/role-lists/:list_key/export.xlsx`
- `GET /api/v1/role-lists/ro/:id/detail`

### list_key chuẩn
- `xe_trong_xuong`
- `ro_cho_phan_cong`
- `ro_cho_kh_dong_y`
- `ro_dang_sua`
- `ro_dung_sua`
- `ro_cho_phu_tung`
- `ro_cho_quyet_toan`
- `ro_da_thanh_toan`
- `xe_vao_xuong_chua_phan_cong` (CSKH)
- `phu_tung_thieu` (Kho)
- `cong_no_mo` (Kế toán)

### Quy tắc
- Filter theo workshop/branch (branch-safe).
- Export yêu cầu permission `reports:export`.


## Phase 8L - Notification Center + SLA Escalation
### DB
- `sla_rules` cấu hình ngưỡng SLA theo trạng thái RO
- `alerts` lưu cảnh báo (dedupe theo rule + RO)

### Engine
- Cron mỗi 5 phút:
  - kiểm tra RO theo `last_status_changed_at`
  - tạo `alerts` + gửi `notifications` theo `sla_rules`

### API
- `GET /api/v1/ops/alerts?status=open|resolved`
- `POST /api/v1/ops/alerts/:id/resolve`
- `GET /api/v1/ops/sla-rules`
- `PUT /api/v1/ops/sla-rules/:rule_key`


## Phase 8M - Escalation nhiều tầng + Dashboard cảnh báo + Meeting Pack SLA
### DB
- `sla_rules.escalation_levels` (jsonb)
- `alerts.last_notified_at`, `alerts.notify_count`

### Engine
- Escalation theo `escalation_levels`:
  - ví dụ: 0 phút -> CVDV, 240 phút -> Quản đốc, 480 phút -> Giám đốc
- Anti-spam: nhắc lại tối thiểu mỗi 60 phút, hoặc khi critical chưa đủ số lần notify.

### API (/api/v1/ops)
- `GET /alerts/dashboard`
- `GET /sla/meeting-pack.xlsx?from=YYYY-MM-DD&to=YYYY-MM-DD`
- `PUT /sla-rules/:rule_key` hỗ trợ `escalation_levels`


## Phase 8N - SLA theo loại RO + KPI theo vai trò theo tháng
### DB
- `repair_orders.payment_type` (BH|IC|FOC|KH)
- `sla_rules.payment_type` (áp dụng riêng theo loại RO)
- `kpi_role_monthly` snapshot KPI theo tháng

### API
- `GET /api/v1/kpi/role-monthly?year=YYYY&month=MM`
- `GET /api/v1/kpi/role-monthly/export.xlsx?year=YYYY&month=MM`


## Phase 8Q - Payroll Integration (bảng lương) + Xuất bảng lương / Phiếu lương
### DB
- `payroll_profiles` (lương cứng, phụ cấp, khấu trừ, ngân hàng)
- `payroll_runs` (bảng lương tháng)
- `payroll_items` (chi tiết từng nhân sự)

### API
- `GET /api/v1/payroll/profiles`
- `PUT /api/v1/payroll/profiles/:user_id`
- `POST /api/v1/payroll/runs/generate?year=YYYY&month=MM`
- `GET /api/v1/payroll/runs?year=YYYY&month=MM`
- `GET /api/v1/payroll/runs/:id/items`
- `POST /api/v1/payroll/runs/:id/lock`
- `POST /api/v1/payroll/runs/:id/mark-paid`
- `GET /api/v1/payroll/runs/:id/export.xlsx`
- `GET /api/v1/payroll/payslip/:user_id?year=YYYY&month=MM`


## Phase 8R - HR: Ca/kíp + Chấm công + OT + Điều chỉnh lương + Ký nhận phiếu lương
### DB
- `hr_shifts`, `hr_shift_assignments`
- `hr_attendance_logs`
- `hr_overtime_requests`
- `payroll_adjustments` (allowance/deduction/violation)
- `payslip_ack` (ký nhận phiếu lương)
- `payroll_items` thêm: `attendance_days`, `minutes_worked`, `minutes_ot`, `allowance_daily_total`, `violation_deduction_total`

### API (/api/v1/hr)
- Shift:
  - `GET /shifts`, `POST /shifts`, `PUT /shifts/:id`
  - `PUT /shift-assignments/:user_id/:work_date`
- Attendance:
  - `POST /attendance/:work_date/check-in`
  - `POST /attendance/:work_date/check-out`
  - `GET /attendance?from&to&user_id`
  - `GET /attendance/export.xlsx?from&to&user_id`
- OT:
  - `POST /ot/:work_date/request`
  - `POST /ot/:id/approve`, `POST /ot/:id/reject`
  - `GET /ot?from&to&user_id`
- Adjustments:
  - `POST /adjustments`
  - `GET /adjustments?year&month&user_id`
- Payslip:
  - `POST /payslip/:run_id/:user_id/ack`


## Phase 8T - Organization Hierarchy (Công ty mẹ → Vùng → XDV → Chi nhánh) + Báo cáo hợp nhất
### DB
- `org_companies`, `org_regions`
- `workshops.company_id`, `workshops.region_id`
- `users.company_id` (giới hạn scope báo cáo hợp nhất)

### API (/api/v1/org)
- Company:
  - `GET /companies`
  - `POST /companies`
  - `PUT /companies/:id`
- Region:
  - `GET /regions?company_id=...`
  - `POST /regions`
  - `PUT /regions/:id`
- Link XDV:
  - `PUT /workshops/:workshop_id/link`
- Hierarchy:
  - `GET /hierarchy?company_id=&region_id=`
- Consolidated:
  - `GET /consolidated/dashboard?company_id=&region_id=`
  - `GET /consolidated/ro-status.xlsx?company_id=&region_id=`


## Phase 8U - Báo cáo hợp nhất doanh thu/lợi nhuận + Ranking XDV/Chi nhánh + Drill-down
### API (/api/v1/org)
- Consolidated Finance:
  - `GET /consolidated/finance?company_id=&region_id=&from=&to=&group=day|month`
  - `GET /consolidated/finance.xlsx?company_id=&region_id=&from=&to=&group=day|month`
- Ranking:
  - `GET /consolidated/ranking/workshops?company_id=&region_id=&from=&to=&metric=revenue|profit`
  - `GET /consolidated/ranking/workshops.xlsx?company_id=&region_id=&from=&to=&metric=revenue|profit`
  - `GET /consolidated/ranking/branches?company_id=&region_id=&from=&to=&metric=revenue|profit`
  - `GET /consolidated/ranking/branches.xlsx?company_id=&region_id=&from=&to=&metric=revenue|profit`
- Drill-down:
  - `GET /consolidated/workshops?company_id=&region_id=&from=&to=`
  - `GET /consolidated/branches?workshop_id=&from=&to=`
  - `GET /consolidated/ros?workshop_id=&branch_id=&from=&to=&q=`
  - `GET /consolidated/ros.xlsx?workshop_id=&branch_id=&from=&to=&q=`

Ghi chú:
- Doanh thu lấy từ `settlements` + `repair_orders.tong_tien_sau_thue`
- Lợi nhuận ước tính = doanh thu - (giờ công * 250,000) - giá vốn phụ tùng (ro_parts.qty * ro_parts.cost_price)


## Phase 8Y - Hiệu năng & Scale (Redis cache + Job Queue + Metrics + Read/Write Split)
### Infra
- Redis: cache report (TTL 60s), queue exports/notifications
- BullMQ: job queue (chạy worker riêng `node src/worker.js`)
- Prometheus metrics: `GET /metrics` (header `x-metrics-token` nếu set `METRICS_TOKEN`)
- PG Read/Write split: `DATABASE_URL` (write), `PGREAD_URL` (read)

### Notes
- Cache hiện áp dụng cho `GET /api/v1/org/consolidated/finance` (có thể mở rộng thêm các report nặng khác).


## Phase 8Z - Hardening/Scale nâng cao (Rate limit Redis + Circuit breaker + Tracing + Debug)
### Env
- `RATE_LIMIT_ENABLED=1`
- `RATE_LIMIT_WINDOW_SEC=60`
- `RATE_LIMIT_MAX_PER_WINDOW=600`
- `OTEL_ENABLED=1`
- `OTEL_SERVICE_NAME=ts-server`
- `PGREAD_URL` (đã có từ 8Y)
- `REDIS_URL` (đã có từ 8Y)

### API
- Debug (admin):
  - `GET /api/v1/debug/diag`
  - `GET /api/v1/debug/event-loop-lag`

### Ghi chú
- Circuit breaker wrapper: `src/infra/circuit.js` (dùng cho webhook/sms/payment...)
- Tracing OpenTelemetry bật theo env, auto-instrument Express/PG.


## Phase 9B - Bộ phát hành thị trường (OpenAPI + Postman + Seed demo + tài liệu bán hàng)
- `npm run openapi` -> tạo `docs/openapi.json`
- `docs/postman_collection.json`
- `npm run seed` -> seed demo tối giản
- `docs/MARKET_PACK.md`


## Phase 9D - Zalo OA + SMS + Email template + Outbox + Webhook (skeleton)
### API (/api/v1/notify)
- Templates:
  - `GET /templates?channel_type=&q=`
  - `POST /templates`
  - `PUT /templates/:id`
- Channels:
  - `GET /channels?channel_type=`
  - `POST /channels`
  - `PUT /channels/:id`
- Outbox:
  - `GET /outbox?status=&from=&to=&q=`
  - `GET /outbox/export.xlsx?status=&from=&to=&q=`
- Send test:
  - `POST /send-test`
- Webhooks:
  - `POST /webhooks/zalo`
  - `POST /webhooks/sms`
  - `POST /webhooks/email`

### Worker
- Chạy worker gửi tin: `node src/worker.js`


## Phase 9E - QC checklist + Bàn giao xe (chữ ký) + Khiếu nại/Bảo hành sau sửa
### API
- QC: `/api/v1/qc`
  - `GET /templates?q=`
  - `POST /templates`
  - `PUT /templates/:id`
  - `POST /runs`
  - `GET /runs?ro_id=`
  - `PUT /runs/:id/items`
  - `POST /runs/:id/submit`
  - `POST /runs/:id/approve`
  - `POST /runs/:id/reject`
  - `GET /runs/:id/export.xlsx`
- Handover: `/api/v1/handover`
  - `POST /forms`
  - `GET /forms?ro_id=`
  - `PUT /forms/:id`
  - `POST /forms/:id/sign`
  - `GET /forms/:id/export.xlsx`
- Tickets: `/api/v1/tickets`
  - `POST /tickets`
  - `GET /tickets?status=&ticket_type=&q=&from=&to=&ro_id=`
  - `PUT /tickets/:id`
  - `GET /tickets/export.xlsx`


## Phase 9F - CSKH automation thật + Feedback (CSAT/NPS) + Dashboard
### API
- CSKH: `/api/v1/cskh`
  - `GET /rules`
  - `POST /rules`
  - `PUT /rules/:id`
  - `POST /automation/run-now`
  - `GET /events?status=&rule_code=&from=&to=`
  - `GET /events/export.xlsx?status=&rule_code=`
  - `GET /dashboard?from=&to=`
  - `GET /dashboard/export.xlsx?from=&to=`
- Public:
  - `POST /api/v1/public/feedback` (header `x-feedback-token` nếu set `FEEDBACK_TOKEN`)

### Env
- `FEEDBACK_PUBLIC_BASE_URL` (để tạo link feedback trong template)
- `FEEDBACK_TOKEN` (bảo vệ endpoint public)


## Phase 9G - Trang feedback mini + Short link + Auto xin đánh giá sau quyết toán
### Public pages
- `GET /feedback?ro_id=` (HTML form)
- `GET /s/:code` (redirect short link)

### Auto review
- Khi Kế toán quyết toán (`POST /api/v1/settlements/:roId`) hệ thống tự enqueue gửi xin đánh giá theo rule `review_request` (nếu đã cấu hình template + FEEDBACK_PUBLIC_BASE_URL).


## Phase 9H - CSAT/NPS nâng cao + cảnh báo tự động + auto ticket khiếu nại
### Public feedback
- `POST /api/v1/public/feedback` giờ sẽ:
  - Tính `nps_bucket` + `severity`
  - Nếu severity != normal: tự tạo `service_tickets` (complaint) + `feedback_alerts`
  - Có thể gửi cảnh báo qua notify nếu cấu hình template/env

### CSKH endpoints bổ sung
- `GET /api/v1/cskh/feedback?from=&to=&q=&severity=`
- `GET /api/v1/cskh/feedback/export.xlsx?severity=`
- `GET /api/v1/cskh/alerts?status=&severity=`
- `POST /api/v1/cskh/alerts/:id/ack`
- `POST /api/v1/cskh/alerts/:id/close`


## Phase 9J - ISO Audit Pack (Trace + Audit Log + Export)
### API
- `GET /api/v1/audit/logs?from=&to=&q=&action=&entity_type=&entity_id=&actor=&trace_id=`
- `GET /api/v1/audit/logs/export.xlsx?from=&to=&q=&action=`
- `GET /api/v1/audit/trace/:trace_id`


## Phase 9K - Audit chống sửa (Append-only + Hash chain + Verify)
### API
- `GET /api/v1/audit/verify?from=&to=` (kiểm tra hash chain, trả bad_id nếu sai)
- `POST /api/v1/audit/seal` (đóng sổ theo ngày: {seal_date, note})
- `GET /api/v1/audit/seals?from=&to=`


## Phase 9L - Export gói ISO (zip)
- `GET /api/v1/audit/iso-pack.zip?from=&to=`
  - verify.json
  - audit_logs.xlsx
  - daily_seals.xlsx
  - ISO_CHECKLIST_TEMPLATE.md
  - MEETING_MINUTES_TEMPLATE.md


## Phase 9R - Ops Dashboard realtime (SSE)
- `GET /api/v1/system/ops/snapshot?workshop_id=`
- `GET /api/v1/system/ops/stream?workshop_id=&interval_ms=3000`


## Phase 9S - TV Dashboard chuẩn xưởng
- `GET /api/v1/tv/snapshot`
- `GET /api/v1/tv/stream?interval_ms=2000` (SSE)


## Admin SaaS (Admin tổng / Admin global)
> Yêu cầu đăng nhập và role: `admin_tong` hoặc `admin_global`

- `GET /admin/saas/overview`
- `GET /admin/saas/revenue/monthly?year=2026`
- `GET /admin/saas/revenue/monthly.xlsx?year=2026`
- `GET /admin/saas/workshops/status?limit=200`
- `GET /admin/saas/workshops/status.xlsx?limit=1000`
- `GET /admin/saas/churn?days=30`
- `GET /admin/saas/top`


---

## Bổ sung Phase 14A–15B (Customer/Push/Analytics/Branch)

### Customer Portal
- POST /api/customer/auth/request-otp
- POST /api/customer/auth/verify-otp
- GET /api/customer/vehicles
- GET /api/customer/vehicles/:vehicleId/ros
- GET /api/customer/ros/:roId
- POST /api/customer/ros/:roId/approve
- GET /api/customer/ros/:roId/quote
- GET /api/customer/ros/:roId/files
- POST /api/customer/feedback

### Device token & Push tracking
- POST /api/devices/register (user/customer)
- POST /internal/push/dispatch (worker)
- POST /api/push/:id/open (tracking)

### Analytics/AI
- GET /api/reports/daily-kpi?from=&to=&branchId=
- GET /api/reports/consolidated?from=&to=
- GET /api/ai/predictions?type=&from=&to=&branchId=
