import { config } from '../config.js';
import { hashPassword } from '../lib/password.js';
import { DEFAULT_WORKSHOP_DEFAULTS } from '../lib/default_sla.js';

async function ensureExtension(db) {
  try {
    await db.query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`);
  } catch (e) {
    console.warn('[initSchema] uuid-ossp:', e?.message || e);
    /* Bảng đã tồn tại thường vẫn dùng được uuid_generate_v4 nếu extension đã có từ trước */
  }
}

export async function initSchema(db) {
  await ensureExtension(db);

  await db.query(`
    CREATE TABLE IF NOT EXISTS xdvs (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        code VARCHAR(50) UNIQUE NOT NULL,
        name VARCHAR(255) NOT NULL,
        address TEXT,
        phone VARCHAR(20),
        email VARCHAR(100),
        director_id UUID,
        status VARCHAR(20) DEFAULT 'Hoạt động',
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS users (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        username VARCHAR(50) UNIQUE NOT NULL,
        password VARCHAR(255) NOT NULL DEFAULT '',
        password_hash VARCHAR(255),
        name VARCHAR(100) NOT NULL,
        role VARCHAR(50) NOT NULL,
        xdv_id UUID REFERENCES xdvs(id) ON DELETE SET NULL,
        is_active BOOLEAN DEFAULT TRUE,
        last_login_at TIMESTAMP WITH TIME ZONE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );
  `);

  for (const col of [
    'password_hash VARCHAR(255)',
    'last_login_at TIMESTAMP WITH TIME ZONE',
    'xdv_id UUID',
  ]) {
    try {
      await db.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS ${col};`);
    } catch {
      /* ignore */
    }
  }

  await db.query(`
    CREATE TABLE IF NOT EXISTS repair_orders (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        ro_code VARCHAR(50) UNIQUE NOT NULL,
        bien_so VARCHAR(20) NOT NULL,
        status VARCHAR(50) NOT NULL DEFAULT 'XE_VAO_XUONG',
        customer_name VARCHAR(100),
        customer_phone VARCHAR(20),
        cvdv_username VARCHAR(50),
        ktv_username VARCHAR(50),
        customer_waiting BOOLEAN DEFAULT FALSE,
        is_insurance BOOLEAN DEFAULT FALSE,
        planned_time_mins INTEGER DEFAULT 60,
        jobs JSONB DEFAULT '[]'::jsonb,
        parts JSONB DEFAULT '[]'::jsonb,
        chat_logs JSONB DEFAULT '[]'::jsonb,
        images JSONB DEFAULT '[]'::jsonb,
        payment_info JSONB,
        urgent_note TEXT,
        customer_note TEXT,
        time_in TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        time_receive TIMESTAMP WITH TIME ZONE,
        time_quote_created TIMESTAMP WITH TIME ZONE,
        time_quote_sent TIMESTAMP WITH TIME ZONE,
        time_quote_approved TIMESTAMP WITH TIME ZONE,
        time_assign TIMESTAMP WITH TIME ZONE,
        time_start TIMESTAMP WITH TIME ZONE,
        time_done TIMESTAMP WITH TIME ZONE,
        time_ready_for_settlement TIMESTAMP WITH TIME ZONE,
        time_paid TIMESTAMP WITH TIME ZONE,
        time_out TIMESTAMP WITH TIME ZONE,
        pauses JSONB DEFAULT '[]'::jsonb,
        audit_history JSONB DEFAULT '[]'::jsonb,
        last_status_changed_at TIMESTAMP WITH TIME ZONE,
        linked_customer VARCHAR(50),
        link_requested_by VARCHAR(50),
        xdv_id UUID REFERENCES xdvs(id) ON DELETE SET NULL,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );
  `);

  const roCols = [
    'customer_name VARCHAR(100)',
    'customer_phone VARCHAR(20)',
    'cvdv_username VARCHAR(50)',
    'ktv_username VARCHAR(50)',
    'jobs JSONB DEFAULT \'[]\'::jsonb',
    'parts JSONB DEFAULT \'[]\'::jsonb',
    'chat_logs JSONB DEFAULT \'[]\'::jsonb',
    'payment_info JSONB',
    'urgent_note TEXT',
    'customer_note TEXT',
    'pauses JSONB DEFAULT \'[]\'::jsonb',
    'audit_history JSONB DEFAULT \'[]\'::jsonb',
    'planned_time_mins INTEGER DEFAULT 60',
    'is_insurance BOOLEAN DEFAULT FALSE',
    'linked_customer VARCHAR(50)',
    'link_requested_by VARCHAR(50)',
    'customer_waiting BOOLEAN DEFAULT FALSE',
    'images JSONB DEFAULT \'[]\'::jsonb',
    'last_status_changed_at TIMESTAMP WITH TIME ZONE',
    'time_receive TIMESTAMP WITH TIME ZONE',
    'xdv_id UUID',
    'cvdv_wo_code VARCHAR(80)',
    'vehicle_activity TEXT',
    'time_quote_created TIMESTAMP WITH TIME ZONE',
    'time_quote_sent TIMESTAMP WITH TIME ZONE',
    'time_quote_approved TIMESTAMP WITH TIME ZONE',
    'time_assign TIMESTAMP WITH TIME ZONE',
    'time_start TIMESTAMP WITH TIME ZONE',
    'time_done TIMESTAMP WITH TIME ZONE',
    'time_ready_for_settlement TIMESTAMP WITH TIME ZONE',
    'time_paid TIMESTAMP WITH TIME ZONE',
    'time_out TIMESTAMP WITH TIME ZONE',
    'fault_diagnosis_at TIMESTAMP WITH TIME ZONE',
  ];
  for (const col of roCols) {
    try {
      await db.query(`ALTER TABLE repair_orders ADD COLUMN IF NOT EXISTS ${col};`);
    } catch {
      /* ignore */
    }
  }

  await db.query(`
    CREATE TABLE IF NOT EXISTS bookings (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        customer_name VARCHAR(100),
        customer_phone VARCHAR(20),
        car_model VARCHAR(100),
        bien_so VARCHAR(20) NOT NULL,
        time VARCHAR(50),
        note TEXT,
        status VARCHAR(50) DEFAULT 'Chờ tiếp nhận',
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS app_settings (
        id SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
        workshop_defaults JSONB NOT NULL DEFAULT '{}'::jsonb,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );
  `);

  await db.query(`
    INSERT INTO app_settings (id, workshop_defaults)
    VALUES (1, $1::jsonb)
    ON CONFLICT (id) DO NOTHING
  `, [JSON.stringify(DEFAULT_WORKSHOP_DEFAULTS)]);

  await db.query(`
    CREATE TABLE IF NOT EXISTS notifications (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        user_id UUID REFERENCES users(id) ON DELETE CASCADE,
        title VARCHAR(255) NOT NULL DEFAULT '',
        body TEXT NOT NULL DEFAULT '',
        data JSONB DEFAULT '{}'::jsonb,
        read_at TIMESTAMP WITH TIME ZONE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS inventory_items (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        xdv_id UUID REFERENCES xdvs(id) ON DELETE SET NULL,
        part_code VARCHAR(80) NOT NULL,
        name TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 0,
        unit VARCHAR(30) DEFAULT '',
        price_in NUMERIC(14,2),
        price_out NUMERIC(14,2),
        location VARCHAR(120),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS company_messages (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        sender_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
        sender_name VARCHAR(255) NOT NULL DEFAULT '',
        sender_role VARCHAR(50) NOT NULL DEFAULT '',
        body TEXT NOT NULL,
        xdv_id UUID REFERENCES xdvs(id) ON DELETE SET NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS company_chat_read_state (
        user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
        last_read_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
    );
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS kh_ad_impressions (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        ad_id VARCHAR(64) NOT NULL,
        user_id UUID REFERENCES users(id) ON DELETE SET NULL,
        revenue_vnd NUMERIC(12, 2) NOT NULL DEFAULT 0,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );
  `);
  await db.query(`
    ALTER TABLE kh_ad_impressions
    ADD COLUMN IF NOT EXISTS revenue_vnd NUMERIC(12, 2) NOT NULL DEFAULT 0;
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS kh_ad_clicks (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        ad_id VARCHAR(64) NOT NULL,
        user_id UUID REFERENCES users(id) ON DELETE SET NULL,
        revenue_vnd NUMERIC(12, 2) NOT NULL DEFAULT 0,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );
  `);

  await db.query(`CREATE INDEX IF NOT EXISTS idx_company_messages_created ON company_messages (created_at DESC);`);
  await db.query(`CREATE INDEX IF NOT EXISTS idx_kh_ad_impressions_ad ON kh_ad_impressions (ad_id, created_at DESC);`);
  await db.query(`CREATE INDEX IF NOT EXISTS idx_kh_ad_clicks_ad ON kh_ad_clicks (ad_id, created_at DESC);`);
  await db.query(`CREATE INDEX IF NOT EXISTS idx_repair_orders_status ON repair_orders (status);`);
  await db.query(`CREATE INDEX IF NOT EXISTS idx_repair_orders_time_in ON repair_orders (time_in DESC);`);
  await db.query(`CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications (user_id, created_at DESC);`);

  await db.query(`
    CREATE TABLE IF NOT EXISTS workshop_data_blobs (
        scope_id TEXT NOT NULL,
        data_key VARCHAR(64) NOT NULL,
        payload JSONB NOT NULL DEFAULT '[]'::jsonb,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        PRIMARY KEY (scope_id, data_key)
    );
  `);

  await bootstrapUsers(db);
  console.log('✅ initSchema: sẵn sàng');
}

async function bootstrapUsers(db) {
  const u = config.bootstrapAdminUsername;
  const p = config.bootstrapAdminPassword;
  if (u && p) {
    const ph = await hashPassword(p);
    await db.query(
      `INSERT INTO users (username, password, password_hash, name, role, is_active)
       VALUES ($1, '', $2, $3, 'ADMIN', true)
       ON CONFLICT (username) DO UPDATE SET
         password = '',
         password_hash = EXCLUDED.password_hash,
         name = EXCLUDED.name,
         role = 'ADMIN',
         is_active = true`,
      [u, ph, config.bootstrapAdminFullname],
    );
    console.log(`✅ Bootstrap admin: ${u}`);
  } else {
    const legacy = await db.query(`SELECT id FROM users WHERE username = 'admin'`);
    if (legacy.rowCount === 0) {
      const ph = await hashPassword('123456');
      await db.query(
        `INSERT INTO users (username, password, password_hash, name, role, is_active)
         VALUES ('admin', '', $1, 'Quản trị viên Tổng', 'ADMIN', true)`,
        [ph],
      );
      console.log('✅ Tạo admin mặc định (admin / 123456).');
    }
  }
}
