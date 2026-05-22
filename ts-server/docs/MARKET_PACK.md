# Bộ tài liệu bán thị trường (Phase 9B)

## 1) Gói sản phẩm đề xuất
- BASIC: 1 XDV, 1 chi nhánh, giới hạn user, module cơ bản
- PRO: nhiều chi nhánh, CRM/CSKH, báo cáo nâng cao
- ENTERPRISE: chuỗi nhiều XDV, hợp nhất toàn hệ thống, RLS/backup/audit, SSO (tuỳ chọn)

## 2) Quy trình onboarding khách hàng (chuẩn)
1) Tạo Company + Plan
2) Khai báo Vùng (nếu có)
3) Tạo XDV (workshop) + Chi nhánh (branch)
4) Tạo user theo vai trò (CVDV/CSKH/Kho/Kế toán/Quản đốc/KTV/Bảo vệ)
5) Import: thư viện phụ tùng, danh sách hẹn, LSC VinFast (nếu dùng)
6) Chạy thử 1 vòng: xe vào xưởng → RO → phân công → sửa chữa → quyết toán → báo cáo

## 3) Demo flow 15 phút (sales)
- Dashboard hợp nhất (org consolidated)
- 1 RO mẫu + timeline
- Kho: xuất/nhập + tồn kho
- Kế toán: quyết toán + công nợ + cashbook
- KPI: thưởng/phạt + payroll
- Export Excel 1-click cho họp

## 4) Checklist triển khai 1 ngày
- Domain + HTTPS
- Fly web + worker
- DB + Redis
- Seed demo (tuỳ chọn)
- Kiểm tra /health, /metrics
