# V32 – Backup/Restore + DR (Disaster Recovery) pack

## 1) Scripts
Trong thư mục `scripts/`:
- `backup_fly_postgres.sh <postgres_app_name> <db_name> [output_dir]`
  - Tạo file `.dump` (custom format) bằng `pg_dump -Fc`
- `restore_fly_postgres.sh <postgres_app_name> <db_name> <dump_file>`
  - Restore bằng `pg_restore --clean --if-exists`
- `verify_restore_smoke.sh`
  - Smoke verify sau restore (login + báo cáo daily)

> Lưu ý: cấp quyền chạy:
- `chmod +x scripts/*.sh`

## 2) Quy ước backup production
- Tần suất khuyến nghị:
  - 1 lần/ngày (ngoài giờ), giữ 14–30 bản
  - Trước mỗi lần deploy lớn, backup thêm 1 bản
- Lưu backup ở nơi khác Fly (S3/Drive/NAS).

## 3) Kịch bản DR chuẩn
1) Phát hiện sự cố (DB corruption/mất dữ liệu/nhầm xóa)
2) Freeze traffic:
   - Scale web về 0 hoặc bật maintenance mode (tuỳ setup)
3) Restore DB từ bản gần nhất
4) Chạy `node src/db/migrate.js` (nếu cần)
5) Smoke verify:
   - `BASE_URL=https://<app>.fly.dev ./scripts/verify_restore_smoke.sh`
6) Mở traffic lại
7) Xuất báo cáo audit/settlement để đối chiếu

## 4) Gợi ý staging restore test
- Tạo 1 app staging + 1 Fly Postgres staging
- Restore bản backup vào staging để test định kỳ (tuần/tháng).
