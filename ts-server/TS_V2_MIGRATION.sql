-- TS XDV V2 - MIGRATION (copy toàn bộ vào Supabase SQL Editor rồi RUN)
-- Mục tiêu:
-- 1) Chống trùng order_code
-- 2) Thêm field phục vụ workflow xưởng + CVDV + cổng
-- 3) Thêm bảng ảnh + lịch sử sự kiện + lịch hẹn (stub)

-- 1) UNIQUE order_code (nếu DB đang trùng, phải dọn trùng trước rồi mới tạo unique)
-- Gợi ý dọn: giữ bản mới nhất, xoá bản cũ (cẩn thận).
-- Sau khi dọn xong mới chạy:
CREATE UNIQUE INDEX IF NOT EXISTS uq_work_orders_order_code ON work_orders(order_code);

-- 2) Thêm các cột workflow (nếu đã có thì bỏ qua)
ALTER TABLE work_orders ADD COLUMN IF NOT EXISTS cvdv_name text;
ALTER TABLE work_orders ADD COLUMN IF NOT EXISTS guard_in_at timestamptz;
ALTER TABLE work_orders ADD COLUMN IF NOT EXISTS guard_out_at timestamptz;
ALTER TABLE work_orders ADD COLUMN IF NOT EXISTS updated_at timestamptz;
ALTER TABLE work_orders ADD COLUMN IF NOT EXISTS tong_tien numeric;
ALTER TABLE work_orders ADD COLUMN IF NOT EXISTS tong_tien_nhan_cong numeric;
ALTER TABLE work_orders ADD COLUMN IF NOT EXISTS tong_tien_phu_tung numeric;

-- 3) Bảng ảnh hiện trạng
CREATE TABLE IF NOT EXISTS work_order_photos (
  id uuid PRIMARY KEY,
  work_order_id uuid NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
  url text NOT NULL,
  note text DEFAULT '',
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_work_order_photos_woid ON work_order_photos(work_order_id);

-- 4) Bảng lịch sử sự kiện (optional, dùng sau)
CREATE TABLE IF NOT EXISTS work_order_events (
  id uuid PRIMARY KEY,
  work_order_id uuid NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
  actor_role text DEFAULT '',
  actor_name text DEFAULT '',
  action text NOT NULL,
  payload jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_work_order_events_woid ON work_order_events(work_order_id);

-- 5) Lịch hẹn (stub)
CREATE TABLE IF NOT EXISTS appointments (
  id uuid PRIMARY KEY,
  bien_so text NOT NULL,
  gio_hen timestamptz NOT NULL,
  cvdv_name text DEFAULT '',
  status text DEFAULT 'scheduled',
  note text DEFAULT '',
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_appointments_bien_so ON appointments(bien_so);
