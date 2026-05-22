# Triển khai TS-Server lên Fly.io (Phase 9A)

## 1) Chuẩn bị
- Đã cài `flyctl`
- Có Postgres (Fly Postgres) và Redis (Upstash Redis hoặc Fly Redis)
- Dùng Node 20

## 2) Biến môi trường bắt buộc
- `DATABASE_URL` (write)
- `PGREAD_URL` (optional)
- `REDIS_URL`
- `JWT_SECRET`
- `METRICS_TOKEN` (optional)
- `RATE_LIMIT_ENABLED=1` (khuyến nghị production)

## 3) Tạo app web
1) Copy `fly.toml.example` -> `fly.toml` và đổi `app = "..."`
2) Deploy:
```bash
fly launch --no-deploy
fly deploy
```

## 4) Tạo app worker (khuyến nghị tách riêng)
1) Copy `fly.worker.toml.example` -> `fly.toml` trong repo worker (hoặc thư mục riêng) và đổi tên app.
2) Deploy worker:
```bash
fly launch --no-deploy
fly deploy
```

## 5) Healthcheck
- Web: `GET /health`
- Metrics: `GET /metrics` (nếu set `METRICS_TOKEN` thì gọi kèm header `x-metrics-token`)

## 6) Quy ước process types
- Web: `node src/index.js`
- Worker: `node src/worker.js`

## 7) CI/CD (GitHub Actions) - mẫu tối giản
Tạo secret:
- `FLY_API_TOKEN`
- `APP_NAME`

Workflow mẫu: `.github/workflows/fly-deploy.yml`

## 8) Tiết kiệm chi phí — tự tắt / tự bật (scale-to-zero)

Fly tính tiền theo **giờ máy chạy**, không phải theo số request. Cấu hình trong `fly.toml`:

```toml
[http_service]
  auto_stop_machines = "stop"   # tắt máy khi không có traffic HTTP
  auto_start_machines = true    # request tới → Fly tự bật máy
  min_machines_running = 0      # cho phép 0 máy (bắt buộc nếu muốn tắt hẳn)
```

Sau khi sửa, deploy lại:

```bash
cd ts-server
fly deploy
```

**Lưu ý quan trọng:**

| Việc | Ảnh hưởng |
|------|-----------|
| Lần mở app đầu sau khi máy đã tắt | **Cold start** — có thể chờ 5–30 giây (hoặc lâu hơn nếu RAM 256MB) |
| Postgres / Redis trên Fly | **Vẫn tính tiền riêng** — chỉ app `ts-server` được scale-to-zero |
| App KH tự làm mới **30 giây** | Mỗi 30s = 1 request → máy **khó tắt** nếu còn ai mở màn KH |
| Worker BullMQ (nếu có) | Cần app worker riêng; worker **không** dùng `http_service` scale-to-zero giống web |

Muốn máy **luôn bật** (ổn định, không cold start): đặt `min_machines_running = 1` và `auto_stop_machines = false`.

**HTTP 502 (body trống)** trên app Flutter: thường do máy Fly **đang tắt** (scale-to-zero) hoặc **chưa nghe cổng** khi proxy chuyển request. `fly.toml` production hiện dùng `min_machines_running = 1` để tránh lỗi này. Sau khi sửa `fly.toml` bắt buộc `fly deploy`.

## 9) Checklist vận hành
- [ ] Bật rate-limit
- [ ] Bật metrics + scrape Grafana/Prometheus
- [ ] Tách worker riêng (queue exports/notifications)
- [ ] Set PGREAD_URL nếu dùng read replica
- [ ] Backup DB định kỳ
- [ ] Đã chọn scale-to-zero hoặc `min_machines_running = 1` theo nhu cầu chi phí / độ trễ
