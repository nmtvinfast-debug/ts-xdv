# TS-XDV Server — triển khai (Fly.io / Docker / local)

Tài liệu này mô tả cách chạy bản **server modular** (`server.js` → `src/index.js`) và các bước deploy an toàn.

## 1. Biến môi trường bắt buộc

| Biến | Ý nghĩa |
|------|---------|
| `DATABASE_URL` | Chuỗi Postgres (Fly Postgres, Supabase, RDS, …). Trên Fly thường gắn sẵn qua `fly postgres attach`. |
| `PORT` | Cổng HTTP (Fly `internal_port` phải trùng; mặc định `3000`). |

Khuyến nghị thêm:

| Biến | Ý nghĩa |
|------|---------|
| `BOOTSTRAP_ADMIN_USERNAME` / `BOOTSTRAP_ADMIN_PASSWORD` / `BOOTSTRAP_ADMIN_FULLNAME` | Tạo tài khoản admin đầu tiên (bcrypt). Xem `.env.example`. |
| `PGSSLMODE=require` | Nếu nhà cung cấp DB bắt buộc SSL. |
| `INTERNAL_API_KEY` | Bảo vệ `POST /api/v1/notifications` (tạo thông báo nội bộ). |
| `IMAGE_RETENTION_DAYS` | Số ngày sau `time_out` để xóa ảnh RO (mặc định 10). |

Không commit file `.env` chứa mật khẩu thật.

## 2. Chạy local

### Chuyển từ bản server cũ (một file `server.js` + `.env` trong thư mục khác)

1. Trong repo **mới**, mở thư mục `ts-server` (cùng cấp với `package.json` modular).
2. **Chép** file `.env` cũ (ví dụ `.../New folder (2)/ts-server/.env`) vào `ts-server/.env` ở đây — giữ `PORT`, `DATABASE_URL` (thường database `ts_xdv` trên `localhost`), `JWT_SECRET`, `AUTO_MIGRATE` nếu có.
3. **Không** dùng lại `server.js` cũ có mật khẩu/host DB **hard-code** trong source; mọi kết nối DB phải qua `DATABASE_URL` trong `.env` (như bản `.env` cũ của bạn).
4. `npm install` rồi `npm run dev` — API lắng nghe `PORT` (mặc định **3000**), Flutter có thể trỏ `http://127.0.0.1:3000`.

`AUTO_MIGRATE=1` (mặc định): chạy `initSchema` khi khởi động (tương đương các hàm `initDatabase` / `initAuthDatabase` / … bản cũ). Đặt `0` nếu bạn cố ý tắt (DB đã có đủ schema và bạn hiểu rủi ro).

```bash
cd ts-server
cp .env.example .env
# Sửa DATABASE_URL trỏ tới Postgres local
npm install
npm run dev
```

Kiểm tra: `GET http://localhost:3000/health`  
Đăng nhập: `POST http://localhost:3000/api/v1/auth/login` với user bootstrap hoặc `admin` / `admin123` nếu dùng tài khoản mặc định dev.

## 3. Deploy Fly.io (rút gọn)

1. Cài [Fly CLI](https://fly.io/docs/hands-on/install-flyctl/), đăng nhập `fly auth login`.
2. Tạo app (nếu chưa có): `fly launch` trong thư mục `ts-server` (hoặc dùng `fly.toml` sẵn có).
3. Tạo / gắn Postgres: `fly postgres create` rồi `fly postgres attach --app <tên-app-ts-server> <tên-db-cluster>` — Fly sẽ inject `DATABASE_URL` vào app.
4. Đặt secret (ví dụ):  
   `fly secrets set BOOTSTRAP_ADMIN_USERNAME=admin BOOTSTRAP_ADMIN_PASSWORD='MậtKhẩuMạnh!' INTERNAL_API_KEY=<random>`
5. Build & chạy: `fly deploy`
6. Xem log: `fly logs`

Đảm bảo `fly.toml` → `[http_service] internal_port` trùng `PORT` (mặc định 3000). `Dockerfile` đã `EXPOSE 3000`.

## 4. API đã có (tầng 1 — nền + Time Rules)

- `GET /health`
- `POST /api/v1/auth/login`, `GET /api/v1/auth/me`
- `GET|POST|PATCH|DELETE` `/api/v1/users` (POST/PATCH lưu bcrypt)
- `GET|POST|PATCH|DELETE` `/api/v1/xdvs`
- `GET|POST|DELETE` `/api/v1/bookings`
- `GET|GET/:id|POST|PATCH|DELETE` `/api/v1/repair-orders` — mốc thời gian, audit, pause/resume, enrich list/detail
- `GET /api/v1/dashboard/summary` — thống kê (XDV hoạt động, user, RO mở, xe trong xưởng, RO chờ quyết toán, breakdown theo `status`)
- `GET|PATCH /api/v1/settings/workshop` — SLA mặc định + merge JSON
- `GET|PATCH .../read|POST` `/api/v1/notifications` (POST cần `INTERNAL_API_KEY` hoặc header `x-internal-key`)
- `GET|POST` `/api/v1/inventory/items`

## 5. Bước tiếp theo (mở rộng theo `docs/API.md`)

1. Thêm migration có phiên bản (thay cho `initSchema` chỉ `CREATE/ALTER IF NOT EXISTS` khi cần kiểm soát schema chặt).
2. JWT thay cho `auth_token_<uuid>` nếu cần hết hạn token / refresh.
3. Middleware phân quyền theo `role` + `xdv_id` (multi-tenant).
4. Triển khai lần lượt các nhóm trong `docs/API.md`: kế toán, kho đầy đủ, quyết toán, báo cáo, SSE, v.v.

## 6. Flutter (sau khi server ổn định)

- Giữ `baseUrl` trỏ tới Fly / domain.
- Gọi thêm `GET /api/v1/auth/me` sau login để đồng bộ profile.
- `GET /api/v1/repair-orders` trả thêm `minutes_in_state`, `state_entered_at`, `open_pause` — có thể dùng cho board mà không cần đổi model cũ (field thừa Flutter bỏ qua được).
