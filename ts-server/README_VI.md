# TS – Backend full nghiệp vụ (Postgres + Express)

Mục tiêu: chạy được **ngay** trên máy bạn (Windows) và deploy lên **Fly.io** + kết nối Postgres.
Toàn bộ thông báo / lỗi **100% tiếng Việt**.

---

## 0) Bạn đang dùng DB nào?
- Backend này dùng **PostgreSQL**.
- Trên Fly.io bạn đã tạo **ts-db** và attach vào **ts-server** => Fly đã set secret `DATABASE_URL` cho app `ts-server`.

---

## 1) Chạy local trên Windows (nhanh nhất)
### 1.1 Cài Node
- Cài Node.js LTS (>= 20)

### 1.2 Clone/giải nén
- Giải nén thư mục backend này vào: `D:\ts-server`

### 1.3 Tạo file `.env`
Tạo file `D:\ts-server\.env`:
```bash
PORT=3000
DATABASE_URL=postgres://USER:PASS@HOST:5432/DBNAME
JWT_SECRET=ts_xdv_change_me
AUTO_MIGRATE=1
```

> Nếu bạn muốn dùng DB trên Fly để chạy local luôn:
- Lấy `DATABASE_URL` trong `fly secrets list -a ts-server` (bạn đã có rồi).

### 1.4 Cài dependencies + run
```powershell
cd D:\ts-server
npm install
npm start
```
Test:
```powershell
Invoke-RestMethod http://localhost:3000/health
Invoke-RestMethod -Method Post -Uri http://localhost:3000/auth/bootstrap -ContentType "application/json" -Body "{}"
```

---

## 2) Deploy lên Fly.io (đã có app `ts-server`)
### 2.1 Kiểm tra `fly.toml`
- Mở `fly.toml` và chắc chắn có:
```toml
app = "ts-server"
```

### 2.2 Deploy
```powershell
cd D:\ts-server
fly deploy -a ts-server
```

Test:
```powershell
Invoke-RestMethod https://ts-server.fly.dev/health
```

---

## 3) Login + gọi API mẫu (đúng endpoint)
### 3.1 Login
```powershell
$body = @{ username="quandoc"; password="123456" } | ConvertTo-Json
$raw = (Invoke-WebRequest -Method Post -Uri "https://ts-server.fly.dev/auth/login" -ContentType "application/json" -Body $body).Content
$token = ($raw | ConvertFrom-Json).token
$headers = @{ Authorization = "Bearer $token" }
```

### 3.2 List work-orders (để app Flutter gọi)
```powershell
Invoke-RestMethod -Method Get -Uri "https://ts-server.fly.dev/work-orders" -Headers $headers
```

### 3.3 List repair-orders (chuẩn)
```powershell
Invoke-RestMethod -Method Get -Uri "https://ts-server.fly.dev/repair-orders" -Headers $headers
```

---

## 4) Map nghiệp vụ end-to-end (API chính)
### 4.1 Bảo vệ nhập xe
`POST /guard/checkin`
```json
{
  "bien_so": "20A-12345",
  "so_khung": "RLL...",
  "ten_kh": "Nguyễn Văn A",
  "sdt_kh": "09...",
  "yeu_cau_kh": "Báo lỗi đèn",
  "location": "Cổng",
  "eta_finish": "2026-02-11T10:00:00.000Z"
}
```

### 4.2 CSKH phân công CVDV
`POST /cskh/assign-cvdv`
```json
{ "ro_id": "...", "cvdv_id": "..." }
```

### 4.3 CVDV tạo/ cập nhật RO (công việc + phụ tùng)
- Xem chi tiết: `GET /repair-orders/:id`
- Update công việc: `POST /cvdv/ro/:id/jobs`
- Update phụ tùng: `POST /cvdv/ro/:id/parts`

### 4.4 Quản đốc phân KTV
`POST /quandoc/assign-ktv`
```json
{ "ro_id": "...", "ktv_id": "..." }
```

### 4.5 KTV bắt đầu / dừng / tiếp tục / hoàn thành
`POST /ktv/ro/:id/status`
```json
{ "action": "start" }
```
- action: `start | pause | resume | finish`
- pause_reason bắt buộc nếu pause.

### 4.6 KTV báo chờ phụ tùng (chỉ ghi chú)
`POST /ktv/ro/:id/part-wait`
```json
{ "note": "Thiếu lọc gió" }
```
→ Server gửi noti cho CVDV. CVDV tra mã + tạo yêu cầu cho Kho.

### 4.7 Kho xuất phụ tùng (trừ tồn)
`POST /kho/ro/:id/issue-parts`
```json
{ "items": [ {"part_code":"1100...","qty":1} ] }
```

### 4.8 CVDV chuyển quyết toán (bắt buộc Kho đã xuất)
`POST /cvdv/ro/:id/request-settlement`

### 4.9 Kế toán thanh toán
`POST /ketoan/ro/:id/pay`
```json
{
  "customer_pay": 1000000,
  "insurance_pay": 0,
  "debt_amount": 0,
  "debt_by": "",
  "deposit_amount": 0
}
```

### 4.10 Bảo vệ cho xe ra cổng
`POST /guard/checkout`
```json
{ "ro_id": "..." }
```

---

## 5) Thư viện phụ tùng (Excel) – quy tắc trùng mã
- Import: `POST /admin/catalog/parts/import` (multipart form-data, field `file`)
- Quy tắc: nếu trùng `part_code` → lấy record có **publish_date mới nhất** (cột D trong file bạn nói).

Tra mã:
`GET /catalog/parts?q=1100&limit=50`

---

## 6) Những role có sẵn (đúng 100%)
`admin_tong | giam_doc | cskh | cvdv | quan_doc | ktv | kho | ke_toan | bao_ve | tv`

> Giám đốc có quyền thay thế làm nghiệp vụ: backend cho phép giám đốc gọi hầu hết API (bạn có thể bật thêm ở Flutter).

---

## 7) Cấu hình Flutter (để gọi backend thật)
Trong app Flutter, đặt baseUrl:
- Local: `http://localhost:3000`
- Fly: `https://ts-server.fly.dev`

Các endpoint app gọi **khớp**:
- Login: `POST /auth/login`
- Me: `GET /auth/me`
- List: `GET /work-orders` hoặc `GET /repair-orders`

---

## 8) Nếu bạn muốn mình map 100% endpoint theo UI Flutter hiện tại
Bạn chỉ cần gửi cho mình:
- File `lib/core/data/api_repository.dart` (hoặc nơi bạn gọi API)
- Danh sách endpoint app đang gọi (log `[REQ]` ở console)

Mình sẽ map lại để **không sửa UI**, chỉ đổi backend.
