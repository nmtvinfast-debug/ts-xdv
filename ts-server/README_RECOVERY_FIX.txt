TS-SERVER RECOVERY FIX

Đây là bản recovery để cứu server boot lại được ngay trên Fly.

Đã sửa:
- package.json -> start/dev chạy server.js ở root
- fly.toml -> app = "ts-server"
- server.js -> server recovery tối thiểu

API có sẵn:
- GET /api/observability/health
- GET /api/observability/routes
- POST /api/v1/auth/login
- GET /api/v1/checkins
- GET /api/v1/work-orders/board
- GET /api/v1/users
- GET /api/v1/admin/workshops
- POST /api/v1/admin/workshops

Tài khoản mặc định:
- admin / 123456

Giám đốc tạo mới:
- đăng nhập bằng username vừa tạo
- mật khẩu mặc định: 123456

Cách dùng:
1. Giải nén
2. copy đè vào thư mục ts-server cũ hoặc dùng riêng thư mục này
3. fly deploy -a ts-server
