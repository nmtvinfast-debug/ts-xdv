import express from 'express';
import { verifyPassword } from '../lib/password.js';

export function createAuthRouter(pool) {
  const r = express.Router();

  r.post('/login', async (req, res) => {
    const { username, password } = req.body || {};
    if (!username || password == null) {
      return res.status(400).json({ error: 'Thiếu username hoặc password' });
    }
    try {
      const result = await pool.query(
        `SELECT * FROM users WHERE username = $1 AND is_active = TRUE`,
        [username],
      );
      if (result.rowCount === 0) {
        return res.status(401).json({ error: 'Sai tài khoản hoặc mật khẩu (hoặc tài khoản bị khóa)' });
      }
      const user = result.rows[0];
      let ok = false;
      if (user.password_hash) {
        ok = await verifyPassword(String(password), user.password_hash);
      } else {
        ok = user.password === String(password);
      }
      if (!ok) {
        return res.status(401).json({ error: 'Sai tài khoản hoặc mật khẩu (hoặc tài khoản bị khóa)' });
      }
      await pool.query(`UPDATE users SET last_login_at = NOW() WHERE id = $1`, [user.id]);
      res.json({
        token: `auth_token_${user.id}`,
        user: {
          id: user.id,
          username: user.username,
          name: user.name,
          role: user.role,
          xdv_id: user.xdv_id,
        },
      });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  r.get('/me', async (req, res) => {
    const raw = req.headers.authorization || '';
    const m = /^Bearer\s+auth_token_([0-9a-f-]{36})$/i.exec(String(raw).trim());
    if (!m) return res.status(401).json({ error: 'Chưa đăng nhập' });
    const id = m[1];
    try {
      const result = await pool.query(
        `SELECT u.id, u.username, u.name, u.role, u.is_active, u.created_at, u.xdv_id, u.last_login_at, x.name AS xdv_name
         FROM users u LEFT JOIN xdvs x ON u.xdv_id = x.id WHERE u.id = $1`,
        [id],
      );
      if (result.rowCount === 0) return res.status(404).json({ error: 'Không tìm thấy user' });
      res.json({ user: result.rows[0] });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  return r;
}
