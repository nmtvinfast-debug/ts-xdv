-- TS_V6_MIGRATION.sql
-- Phase 14A-15B: Customer Portal, Push nâng cao, Analytics/AI, Multi-branch reporting, Market expansion settings

BEGIN;

-- =========
-- 0) ORG / BRANCH (nếu hệ thống đã có bảng tương tự thì các câu lệnh IF NOT EXISTS sẽ không ảnh hưởng)
-- =========
CREATE TABLE IF NOT EXISTS org_companies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ten_cong_ty TEXT NOT NULL,
  ma_cong_ty TEXT UNIQUE,
  dia_chi TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Workshop/XDV có thể đã tồn tại; nếu đã có bảng workshops thì bỏ qua tạo mới.
CREATE TABLE IF NOT EXISTS org_workshops (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID REFERENCES org_companies(id) ON DELETE SET NULL,
  ten_xuong TEXT NOT NULL,
  dia_chi TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS org_branches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workshop_id UUID REFERENCES org_workshops(id) ON DELETE CASCADE,
  ten_chi_nhanh TEXT NOT NULL,
  dia_chi TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE users ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES org_companies(id) ON DELETE SET NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES org_branches(id) ON DELETE SET NULL;

-- =========
-- 1) CUSTOMER PORTAL
-- =========
CREATE TABLE IF NOT EXISTS customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workshop_id UUID NOT NULL REFERENCES workshops(id) ON DELETE CASCADE,
  ho_ten TEXT,
  so_dien_thoai TEXT NOT NULL,
  email TEXT,
  ghi_chu TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_customers_workshop_phone ON customers(workshop_id, so_dien_thoai);

-- map khách - xe (trường hợp 1 khách nhiều xe hoặc xe thay chủ)
CREATE TABLE IF NOT EXISTS customer_vehicles_map (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workshop_id UUID NOT NULL REFERENCES workshops(id) ON DELETE CASCADE,
  customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  vehicle_id UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
  is_primary BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_customer_vehicle_unique ON customer_vehicles_map(workshop_id, customer_id, vehicle_id);

-- OTP (nếu dùng OTP nội bộ; nếu dùng nhà cung cấp OTP thì vẫn nên lưu audit tối thiểu)
CREATE TABLE IF NOT EXISTS customer_otps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workshop_id UUID NOT NULL REFERENCES workshops(id) ON DELETE CASCADE,
  so_dien_thoai TEXT NOT NULL,
  otp_hash TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_customer_otps_phone ON customer_otps(workshop_id, so_dien_thoai, expires_at DESC);

-- =========
-- 2) DEVICE TOKENS + PUSH TRACKING
-- =========
CREATE TABLE IF NOT EXISTS device_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workshop_id UUID REFERENCES workshops(id) ON DELETE CASCADE,
  owner_type TEXT NOT NULL CHECK (owner_type IN ('USER','CUSTOMER')),
  owner_id UUID NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('ANDROID','IOS','WEB')),
  token TEXT NOT NULL,
  app_version TEXT,
  device_model TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_seen_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_device_tokens_owner_token ON device_tokens(owner_type, owner_id, token);

CREATE TABLE IF NOT EXISTS push_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workshop_id UUID REFERENCES workshops(id) ON DELETE CASCADE,
  event_code TEXT NOT NULL,
  priority TEXT NOT NULL DEFAULT 'MEDIUM' CHECK (priority IN ('HIGH','MEDIUM','LOW')),
  channel TEXT NOT NULL DEFAULT 'PUSH',
  target_owner_type TEXT NOT NULL CHECK (target_owner_type IN ('USER','CUSTOMER')),
  target_owner_id UUID NOT NULL,
  ro_id UUID,
  payload JSONB NOT NULL,
  rendered_title TEXT,
  rendered_body TEXT,
  status TEXT NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED','SENT','FAILED')),
  error_message TEXT,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_push_events_target ON push_events(target_owner_type, target_owner_id, created_at DESC);

CREATE TABLE IF NOT EXISTS push_receipts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  push_event_id UUID NOT NULL REFERENCES push_events(id) ON DELETE CASCADE,
  device_token_id UUID REFERENCES device_tokens(id) ON DELETE SET NULL,
  provider_message_id TEXT,
  delivered_at TIMESTAMPTZ,
  opened_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========
-- 3) ANALYTICS SNAPSHOT + AI PREDICTIONS
-- =========
CREATE TABLE IF NOT EXISTS report_daily_kpi (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workshop_id UUID NOT NULL REFERENCES workshops(id) ON DELETE CASCADE,
  branch_id UUID REFERENCES org_branches(id) ON DELETE SET NULL,
  ngay DATE NOT NULL,
  kpi JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_report_daily_kpi ON report_daily_kpi(workshop_id, branch_id, ngay);

CREATE TABLE IF NOT EXISTS ai_predictions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workshop_id UUID NOT NULL REFERENCES workshops(id) ON DELETE CASCADE,
  branch_id UUID REFERENCES org_branches(id) ON DELETE SET NULL,
  loai_du_doan TEXT NOT NULL, -- VD: 'FORECAST_CHECKIN','PARTS_SHORTAGE','RO_DELAY','CHURN','UPSELL'
  ngay_du_doan DATE NOT NULL,
  gia_tri NUMERIC,
  confidence NUMERIC,
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_ai_predictions_lookup ON ai_predictions(workshop_id, branch_id, loai_du_doan, ngay_du_doan DESC);

-- =========
-- 4) WORKSHOP SETTINGS (market expansion config-as-data)
-- =========
CREATE TABLE IF NOT EXISTS workshop_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workshop_id UUID NOT NULL UNIQUE REFERENCES workshops(id) ON DELETE CASCADE,
  settings JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMIT;
