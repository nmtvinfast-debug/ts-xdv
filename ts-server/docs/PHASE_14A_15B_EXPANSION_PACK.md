# TS-XDV – Phase 14A → 15B (Expansion Pack) – Tài liệu triển khai production

> Mục tiêu: hoàn thiện hệ thống TS-XDV thành nền tảng **chuỗi xưởng** (multi-branch), có **cổng khách hàng** mạnh, **push nâng cao**, **phân tích nâng cao + AI dự đoán**, và “market expansion pack” để triển khai nhanh cho khách hàng mới.

Tài liệu này bổ sung cho các Phase trước (đặc biệt 13D Template Engine, Master Data, Export/Audit) để ra **hệ thống hoàn chỉnh**.

---

## 0) Nguyên tắc chung (đã chốt)
- Toàn bộ UI + thông báo + lỗi: **100% tiếng Việt**.
- RBAC theo vai trò; dữ liệu **cô lập theo XDV/workshop** (multi-tenant isolation).
- Log/Audit/Export theo chuẩn doanh nghiệp.
- Chuẩn hóa workflow RO + mốc thời gian xe/RO.
- Chi phí giờ công chuẩn KTV: **250.000 VND/giờ** (dùng cho P&L/hiệu suất).

---

# PHASE 14A – Customer Portal nâng cấp (Cổng khách hàng)

## 14A.1 Mục tiêu nghiệp vụ
1) Khách theo dõi tiến độ xe/RO theo thời gian thực (timeline + trạng thái + lý do dừng).
2) Khách duyệt báo giá online: Đồng ý / Không đồng ý (có ghi chú, lưu thời điểm + người xác nhận).
3) Khách thanh toán (tùy cấu hình xưởng): QR chuyển khoản / tiền mặt / cổng thanh toán.
4) Khách xem lịch sử sửa chữa, hóa đơn PDF, bảo hành, khuyến nghị bảo dưỡng.
5) CSKH/CVDV có kênh nhắn tin/trao đổi với khách (chat), ghi nhận toàn bộ trao đổi vào RO.

## 14A.2 Các màn hình chính (Customer App / Customer Web)
- **Đăng nhập/OTP** (SĐT) → chọn xe (nếu khách có nhiều xe).
- **Xe của tôi**: danh sách xe, biển số, model, km (nếu có), lần vào xưởng gần nhất.
- **RO đang xử lý**: timeline + trạng thái + vị trí xe + dự kiến hoàn tất.
- **Báo giá**: danh sách hạng mục công việc + phụ tùng + VAT + giảm giá + tổng; nút Đồng ý / Không đồng ý.
- **Thanh toán**: chi tiết số tiền; QR; lịch sử thanh toán.
- **Lịch sử**: các RO đã hoàn tất; tải PDF (hóa đơn/biên bản).
- **Nhắc lịch bảo dưỡng**: theo km/thời gian; đăng ký nhận nhắc.
- **Phản hồi**: chấm điểm + góp ý.

## 14A.3 Thiết kế xác thực khách hàng
### Phương án chuẩn (khuyến nghị)
- Customer login bằng **OTP SMS** (hoặc OTP nội bộ giai đoạn đầu).
- Backend phát JWT có `sub=customerId`, `workshopId`, `scopes=["customer"]`.
- Khách chỉ truy cập:
  - xe thuộc customerId
  - RO thuộc xe đó
  - file/pdf thuộc RO đó

### Ràng buộc bảo mật
- Không cho phép query RO theo id nếu không thuộc customer.
- File download dùng signed URL hoặc route kiểm quyền.

## 14A.4 API (gợi ý)
- `POST /api/customer/auth/request-otp` { phone }
- `POST /api/customer/auth/verify-otp` { phone, otp } -> { token }
- `GET /api/customer/vehicles`
- `GET /api/customer/vehicles/:vehicleId/ros?status=ACTIVE|DONE`
- `GET /api/customer/ros/:roId`
- `POST /api/customer/ros/:roId/approve` { approved: true, note? }
- `POST /api/customer/ros/:roId/approve` { approved: false, note }
- `GET /api/customer/ros/:roId/quote`
- `POST /api/customer/ros/:roId/payment-intent` (nếu tích hợp cổng)
- `GET /api/customer/ros/:roId/files` (pdf)
- `POST /api/customer/feedback` { roId, rating, comment? }
- `GET /api/customer/maintenance/reminders`
- `POST /api/customer/maintenance/reminders` { vehicleId, rule: KM|TIME, value }

## 14A.5 Notification (liên kết Template Engine 13D)
Các event đề xuất cho khách:
- `CUSTOMER_QUOTE_READY` (đã có báo giá)
- `CUSTOMER_APPROVED` / `CUSTOMER_REJECTED`
- `CUSTOMER_PAYMENT_REQUESTED`
- `VEHICLE_STATUS_CHANGED`
- `VEHICLE_READY_FOR_PICKUP`

Payload phải match schema của Template Engine.

---

# PHASE 14B – Mobile Push nâng cao

## 14B.1 Mục tiêu
- Push đúng người – đúng thời điểm – đúng nội dung (theo vai trò, RO, ưu tiên).
- Không mất push: có queue + retry + theo dõi delivery/open.
- Có “push im lặng” để đồng bộ trạng thái nền (nếu cần).

## 14B.2 Kiến trúc kỹ thuật
- Bảng lưu thiết bị + token (FCM/APNs).
- Push service: nhận job từ queue (BullMQ/Redis hoặc DB outbox).
- Template Engine render nội dung theo channel `PUSH`.
- Tracking: sent/delivered/open (tối thiểu sent + open).

## 14B.3 Quy tắc push theo vai trò (gợi ý)
- Quản đốc: RO mới từ CVDV, phụ tùng về, RO quá SLA.
- KTV: việc mới, nhắc tiếp tục sau khi dừng, phụ tùng đã về cho việc của mình.
- Kho: danh sách phụ tùng thiếu cần xử lý, cảnh báo tồn kho thấp.
- Kế toán: RO chuyển quyết toán, công nợ quá hạn.
- Giám đốc: cảnh báo KPI, xe tồn xưởng lâu, doanh thu/ngày thấp bất thường.
- Khách hàng: báo giá, tiến độ, xe sẵn sàng bàn giao.

## 14B.4 SLA + chống spam
- Có “cooldown” theo eventCode+userId+roId (ví dụ 3–10 phút).
- Gom cụm (batch) nếu nhiều event giống nhau (ví dụ phụ tùng về nhiều món).
- Ưu tiên: HIGH/MEDIUM/LOW.

---

# PHASE 14C – Advanced Analytics (AI Predictive)

## 14C.1 Mục tiêu
- Báo cáo vận hành sâu + dự đoán:
  - dự đoán lượng xe vào xưởng theo ngày/tuần
  - dự đoán thiếu phụ tùng (đề xuất đặt hàng)
  - dự đoán RO trễ tiến độ (tắc nghẽn)
  - churn/khách không quay lại
  - gợi ý gói dịch vụ phù hợp

## 14C.2 Dữ liệu đầu vào (tối thiểu)
- RO timeline (mốc thời gian đã chốt)
- Job timeline theo KTV
- Part usage (xuất kho theo RO)
- Doanh thu, giảm giá, VAT, công nợ, thanh toán
- Lịch sử khách: số lần quay lại, khoảng cách giữa 2 lần

## 14C.3 Data pipeline (khuyến nghị)
- **OLTP**: Postgres chính (TS).
- **Analytics store**:
  - Giai đoạn 1: bảng “fact_*” trong cùng Postgres (partition theo tháng).
  - Giai đoạn 2: tách sang kho dữ liệu (BigQuery/ClickHouse) nếu cần.
- ETL:
  - job chạy theo ngày (00:30) + incremental theo `updated_at`.
  - tạo snapshot KPI ngày.

## 14C.4 AI Predictive (gợi ý triển khai thực tế)
- Giai đoạn 1 (nhanh, dễ triển khai):
  - mô hình thống kê/ML nhẹ: Prophet/ARIMA (forecast xe vào), Logistic Regression (churn), XGBoost (trễ RO).
  - chạy batch 1 lần/ngày.
- Giai đoạn 2:
  - online features + realtime anomaly detection.
- Output:
  - bảng `ai_predictions` (theo workshop/branch/date/type) + confidence.

## 14C.5 Dashboard analytics (role Giám đốc/Quản lý chuỗi)
- Tồn xưởng theo trạng thái
- SLA trễ theo công đoạn (chờ duyệt/chờ phụ tùng/chờ KTV/chờ quyết toán)
- Hiệu suất KTV: giờ công chuẩn vs thực tế; P&L
- Top lỗi/quy trình tắc nghẽn
- Doanh thu/ngày + cảnh báo bất thường

---

# PHASE 15A – Multi-branch advanced reporting (Chuỗi chi nhánh)

## 15A.1 Mục tiêu
- Tổ chức theo mô hình:
  - Company/Org → Region (tuỳ chọn) → Workshop/XDV → Branch/Chi nhánh
- Báo cáo hợp nhất:
  - theo Company (toàn chuỗi)
  - theo Workshop
  - theo Branch

## 15A.2 Ràng buộc dữ liệu
- Tất cả bảng nghiệp vụ phải có `workshop_id` và (nếu có) `branch_id`.
- RBAC:
  - Super Admin (cấp chuỗi) xem toàn bộ company
  - Giám đốc workshop xem workshop mình
  - Quản lý chi nhánh chỉ xem branch mình (nếu phân cấp)

## 15A.3 Báo cáo nâng cao (gợi ý)
- P&L theo chi nhánh (doanh thu - chi phí giờ công - chi phí phụ tùng)
- Công nợ tập trung: theo khách/đối tác/bảo hiểm
- Hiệu suất: RO/ngày, giờ công/ngày, tỉ lệ quay lại
- Phễu vận hành: check-in → báo giá → duyệt → sửa → quyết toán → checkout

## 15A.4 Export chuẩn doanh nghiệp
- Excel/PDF:
  - có header doanh nghiệp
  - filter range ngày
  - đóng dấu thời điểm xuất + người xuất (audit)

---

# PHASE 15B – Market Expansion Pack (Mở rộng thị trường)

## 15B.1 Mục tiêu
- Triển khai nhanh cho khách mới trong 1–3 ngày:
  - tạo company + workshop + branch
  - tạo user theo vai trò
  - import master data (phụ tùng, gói dịch vụ, danh sách hẹn)
  - bật cấu hình tích hợp (nếu có)

## 15B.2 Gói cấu hình (config as data)
- bảng `workshop_settings`:
  - bật/tắt OTP khách, bật/tắt thanh toán online
  - mẫu template override
  - cấu hình VAT mặc định
  - SLA cảnh báo
  - cấu hình phân quyền theo branch

## 15B.3 Tích hợp đối tác (khuyến nghị chuẩn hóa)
- Insurance: trạng thái bảo hiểm, thanh toán bảo hiểm
- OEM: thư viện phụ tùng, quy trình bảo hành
- Payment: VNPAY/MoMo/QR chuyển khoản
- SMS: gửi OTP + nhắc lịch

## 15B.4 Vận hành + bảo mật
- Monitoring: uptime, error rate, queue depth, DB slow query
- Rate limit theo IP + user
- Audit log toàn hệ thống
- Data retention:
  - ảnh check-in xe tự xoá sau N ngày (đã chốt 10 ngày) hoặc chuyển sang object storage.

---

# 16) Danh sách bảng dữ liệu cần bổ sung (tóm tắt)
(Chi tiết migration ở `TS_V6_MIGRATION.sql`)
- `customers`, `customer_vehicles_map`
- `customer_otps`, `customer_sessions` (nếu không dùng chung auth)
- `device_tokens` (user/customer)
- `push_events`, `push_receipts` (tracking)
- `org_companies`, `org_workshops`, `org_branches` (nếu chưa có)
- `report_daily_kpi` (snapshot)
- `ai_predictions`

---

# 17) Checklist “ra hệ thống hoàn chỉnh”
- [ ] Customer Portal + OTP + quyền truy cập theo customer
- [ ] Push service + queue + retry + tracking
- [ ] Analytics snapshot + dashboard drilldown
- [ ] Multi-branch reporting + RBAC chuỗi
- [ ] Market pack + onboarding script + config templates
- [ ] Giám sát/backup/audit + quy tắc retention

---

## Phụ lục: KPI khuyến nghị theo tuần/tháng
- Thời gian tồn xưởng trung bình
- Tỉ lệ RO trễ SLA
- Giờ công/KTV/ngày
- Doanh thu/RO
- Tỉ lệ khách quay lại 30/60/90 ngày
- Tỉ lệ báo giá được duyệt
