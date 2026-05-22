/**
 * Đặt / đổi tài khoản ADMIN trên DB (bcrypt).
 * Chạy: node scripts/set-admin-user.mjs
 * Hoặc: ADMIN_USERNAME=... ADMIN_PASSWORD=... node scripts/set-admin-user.mjs
 */
import 'dotenv/config';
import { createPool } from '../src/db/pool.js';
import { hashPassword } from '../src/lib/password.js';

const USERNAME = (process.env.ADMIN_USERNAME || process.env.BOOTSTRAP_ADMIN_USERNAME || 'b4nggj4').trim();
const PASSWORD = process.env.ADMIN_PASSWORD || process.env.BOOTSTRAP_ADMIN_PASSWORD || 'toan2707';
const FULLNAME = (process.env.BOOTSTRAP_ADMIN_FULLNAME || 'Quản trị viên Tổng').trim();

const pool = createPool();

async function main() {
  const ph = await hashPassword(PASSWORD);
  const client = await pool.connect();
  try {
    const existing = await client.query(`SELECT id, username FROM users WHERE username = $1`, [USERNAME]);
    if (existing.rowCount > 0) {
      await client.query(
        `UPDATE users SET password = '', password_hash = $1, name = $2, role = 'ADMIN', is_active = true WHERE username = $3`,
        [ph, FULLNAME, USERNAME],
      );
      console.log(`✅ Đã cập nhật mật khẩu ADMIN: ${USERNAME}`);
    } else {
      await client.query(
        `INSERT INTO users (username, password, password_hash, name, role, is_active)
         VALUES ($1, '', $2, $3, 'ADMIN', true)`,
        [USERNAME, ph, FULLNAME],
      );
      console.log(`✅ Đã tạo ADMIN mới: ${USERNAME}`);
    }

    const legacy = await client.query(
      `UPDATE users SET is_active = false
       WHERE role ILIKE '%admin%' AND username <> $1 AND username IN ('admin', '01', '02')`,
      [USERNAME],
    );
    if (legacy.rowCount > 0) {
      console.log(`ℹ️ Đã khóa ${legacy.rowCount} tài khoản ADMIN cũ (admin/01/02).`);
    }
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
