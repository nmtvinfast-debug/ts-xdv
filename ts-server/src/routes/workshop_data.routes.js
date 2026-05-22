import express from 'express';
import { createAuthMiddleware, normRole } from '../middleware/user_permissions.js';

const ALLOWED_KEYS = new Set([
  'kho_db',
  'kho_history',
  'uom_db',
  'staff_db',
  'ke_toan_tracking',
]);

function scopeId(req) {
  const role = normRole(req.user?.role);
  if (role === 'ADMIN' && req.query.xdv_id) {
    return String(req.query.xdv_id).trim();
  }
  const id = req.user?.xdv_id;
  return id ? String(id) : 'global';
}

export function createWorkshopDataRouter(pool) {
  const r = express.Router();
  const auth = createAuthMiddleware(pool);

  r.get('/:key', auth, async (req, res) => {
    const key = String(req.params.key || '').trim();
    if (!ALLOWED_KEYS.has(key)) {
      return res.status(400).json({ error: 'Khóa dữ liệu không hợp lệ' });
    }
    const scope = scopeId(req);
    try {
      const result = await pool.query(
        `SELECT payload, updated_at FROM workshop_data_blobs WHERE scope_id = $1 AND data_key = $2`,
        [scope, key],
      );
      if (result.rowCount === 0) {
        return res.json([]);
      }
      res.json(result.rows[0].payload ?? []);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  r.put('/:key', auth, async (req, res) => {
    const key = String(req.params.key || '').trim();
    if (!ALLOWED_KEYS.has(key)) {
      return res.status(400).json({ error: 'Khóa dữ liệu không hợp lệ' });
    }
    const scope = scopeId(req);
    const payload = req.body;
    if (payload === undefined || payload === null) {
      return res.status(400).json({ error: 'Thiếu nội dung JSON' });
    }
    try {
      const result = await pool.query(
        `INSERT INTO workshop_data_blobs (scope_id, data_key, payload, updated_at)
         VALUES ($1, $2, $3::jsonb, NOW())
         ON CONFLICT (scope_id, data_key) DO UPDATE SET
           payload = EXCLUDED.payload,
           updated_at = NOW()
         RETURNING updated_at`,
        [scope, key, JSON.stringify(payload)],
      );
      res.json({ ok: true, updated_at: result.rows[0]?.updated_at });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  return r;
}
