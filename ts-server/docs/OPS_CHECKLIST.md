# Checklist vận hành nội bộ (TS-Server)

## Monitoring
- [ ] /metrics hoạt động, Prometheus scrape OK
- [ ] Alerts: CPU/RAM, 5xx rate, latency p95, DB slow queries
- [ ] Event-loop lag endpoint theo dõi bất thường

## Database
- [ ] Migrations chạy sạch
- [ ] Read replica (PGREAD_URL) nếu cần
- [ ] Backup daily + test restore

## Queue/Worker
- [ ] Worker deploy riêng, auto restart
- [ ] Redis ổn định, memory đủ
- [ ] Export nặng chạy qua queue (mở rộng dần)

## Security
- [ ] JWT secret mạnh
- [ ] Rate-limit bật
- [ ] METRICS_TOKEN bật nếu public endpoint

## Release
- [ ] Tag version
- [ ] Rollback plan
