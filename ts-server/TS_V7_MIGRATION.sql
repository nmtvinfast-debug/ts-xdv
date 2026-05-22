-- TS_V7_MIGRATION.sql
-- Cột time_receive: PATCH RO khi CSKH gán CVDV lần đầu (repair_orders.routes.js).
-- DB cũ có bảng repair_orders nhưng thiếu cột → lỗi "column time_receive does not exist".

BEGIN;

ALTER TABLE repair_orders ADD COLUMN IF NOT EXISTS time_receive TIMESTAMP WITH TIME ZONE;

COMMIT;
