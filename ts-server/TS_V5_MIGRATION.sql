-- TS_V5_MIGRATION.sql
-- Phase 2: phân công theo job, stopwatch, yêu cầu phụ tùng, chuẩn hóa cột còn thiếu

BEGIN;

-- 1) ro_jobs: gán KTV + trạng thái + stopwatch
ALTER TABLE ro_jobs ADD COLUMN IF NOT EXISTS ktv_id UUID REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE ro_jobs ADD COLUMN IF NOT EXISTS trang_thai TEXT NOT NULL DEFAULT 'chua_bat_dau';
ALTER TABLE ro_jobs ADD COLUMN IF NOT EXISTS thoi_gian_bat_dau TIMESTAMPTZ;
ALTER TABLE ro_jobs ADD COLUMN IF NOT EXISTS thoi_gian_dung TIMESTAMPTZ;
ALTER TABLE ro_jobs ADD COLUMN IF NOT EXISTS thoi_gian_tiep_tuc TIMESTAMPTZ;
ALTER TABLE ro_jobs ADD COLUMN IF NOT EXISTS thoi_gian_hoan_thanh TIMESTAMPTZ;
ALTER TABLE ro_jobs ADD COLUMN IF NOT EXISTS ly_do_dung TEXT DEFAULT '';
ALTER TABLE ro_jobs ADD COLUMN IF NOT EXISTS ghi_chu_dung TEXT DEFAULT '';
ALTER TABLE ro_jobs ADD COLUMN IF NOT EXISTS ket_qua_kiem_tra TEXT DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_ro_jobs_ktv ON ro_jobs(ktv_id);

-- 2) repair_orders: bổ sung các cột đang được routes sử dụng (tương thích)
ALTER TABLE repair_orders ADD COLUMN IF NOT EXISTS note TEXT DEFAULT '';
ALTER TABLE repair_orders ADD COLUMN IF NOT EXISTS time_assigned_ktv TIMESTAMPTZ;
ALTER TABLE repair_orders ADD COLUMN IF NOT EXISTS time_start_repair TIMESTAMPTZ;
ALTER TABLE repair_orders ADD COLUMN IF NOT EXISTS time_pause_repair TIMESTAMPTZ;
ALTER TABLE repair_orders ADD COLUMN IF NOT EXISTS time_resume_repair TIMESTAMPTZ;
ALTER TABLE repair_orders ADD COLUMN IF NOT EXISTS time_finish_repair TIMESTAMPTZ;
ALTER TABLE repair_orders ADD COLUMN IF NOT EXISTS pause_reason TEXT DEFAULT '';

-- 3) part_requests: yêu cầu phụ tùng thiếu (KTV -> CVDV)
CREATE TABLE IF NOT EXISTS part_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workshop_id UUID NOT NULL REFERENCES workshops(id) ON DELETE CASCADE,
  ro_id UUID NOT NULL REFERENCES repair_orders(id) ON DELETE CASCADE,
  job_id UUID REFERENCES ro_jobs(id) ON DELETE SET NULL,
  requested_by UUID REFERENCES users(id) ON DELETE SET NULL,
  approved_by UUID REFERENCES users(id) ON DELETE SET NULL,
  received_by UUID REFERENCES users(id) ON DELETE SET NULL,
  part_code TEXT,
  part_name TEXT NOT NULL,
  qty NUMERIC NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'requested', -- requested|approved|ordered|received|rejected
  note TEXT DEFAULT '',
  approved_at TIMESTAMPTZ,
  received_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_part_requests_ro ON part_requests(ro_id);
CREATE INDEX IF NOT EXISTS idx_part_requests_status ON part_requests(status);

COMMIT;
