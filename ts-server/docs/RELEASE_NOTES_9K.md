# Release Notes - Phase 9K
Ngày: 2026-02-16

- Audit log append-only: chặn UPDATE/DELETE bằng trigger
- Thêm hash chain: prev_hash + row_hash (sha256) khi ghi log
- API verify hash chain + daily seal (đóng sổ) để kiểm toán
