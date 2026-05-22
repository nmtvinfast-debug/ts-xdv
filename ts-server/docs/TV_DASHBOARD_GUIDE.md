# Phase 9S - TV Dashboard API chuẩn xưởng (Realtime)

## API
- GET /api/v1/tv/snapshot
- GET /api/v1/tv/stream?interval_ms=2000 (SSE)

## Output chính
- tong_xe_trong_xuong
- danh_sach_xe[]: bien_so, vi_tri_xe, trang_thai, tien_do, mau_canh_bao, canh_bao_sla[], phu_tung_cho[]

## Ghi chú DB
Module cố gắng đọc các bảng/cột phổ biến:
- repair_orders
- ro_sla_violations (nếu có)
- parts_shortages (nếu có)
Nếu bảng chưa tồn tại, phần đó trả rỗng.
