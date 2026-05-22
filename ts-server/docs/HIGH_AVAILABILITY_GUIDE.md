# Phase 9P - High Availability + Failover Design

## 1) Read/Write Split
Env:
- DATABASE_URL (primary write)
- DATABASE_READ_URL (replica read)

query(sql, params, { read:true }) để đọc từ replica.

## 2) Health Check
GET /api/v1/system/health

Trả:
- uptime
- memory
- db.write
- db.read

## 3) Failover Strategy (khuyến nghị)
- Fly.io / Cloud: deploy >=2 instances
- DB replica + automatic failover
- Redis queue (đã có ở phase trước)
- Backup daily (Phase 9N)

## 4) Production Checklist
- Enable autoscale
- Enable monitoring (metrics endpoint)
- Separate read/write connection
