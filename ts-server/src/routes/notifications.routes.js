import express from 'express';

function parseUserId(req) {
  const raw = req.headers.authorization || '';
  const m = /^Bearer\s+auth_token_([0-9a-f-]{36})$/i.exec(String(raw).trim());
  return m ? m[1] : null;
}

export function createNotificationsRouter(pool) {
  const r = express.Router();

  r.get('/', async (req, res) => {
    const uid = parseUserId(req);
    if (!uid) return res.status(401).json({ error: 'Chưa đăng nhập' });
    try {
      const result = await pool.query(
        `SELECT * FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT 200`,
        [uid],
      );
      res.json(result.rows);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  r.patch('/:id/read', async (req, res) => {
    const uid = parseUserId(req);
    if (!uid) return res.status(401).json({ error: 'Chưa đăng nhập' });
    try {
      const result = await pool.query(
        `UPDATE notifications SET read_at = NOW() WHERE id = $1 AND user_id = $2 RETURNING *`,
        [req.params.id, uid],
      );
      if (result.rowCount === 0) return res.status(404).json({ error: 'Không tìm thấy thông báo' });
      res.json(result.rows[0]);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  /** Tạo thông báo nội bộ (cron / admin gọi sau này; có thể bảo vệ bằng INTERNAL_API_KEY) */
  r.post('/', async (req, res) => {
    if (!process.env.INTERNAL_API_KEY) {
      return res.status(503).json({ error: 'POST /notifications tắt: chưa cấu hình INTERNAL_API_KEY' });
    }
    const key = req.headers['x-internal-key'] || req.headers['x-api-key'];
    if (key !== process.env.INTERNAL_API_KEY) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    const { user_id, title, body, data } = req.body || {};
    if (!user_id) return res.status(400).json({ error: 'Thiếu user_id' });
    try {
      const result = await pool.query(
        `INSERT INTO notifications (user_id, title, body, data) VALUES ($1, $2, $3, $4::jsonb) RETURNING *`,
        [user_id, title || '', body || '', JSON.stringify(data ?? {})],
      );
      res.status(201).json(result.rows[0]);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  return r;
}
