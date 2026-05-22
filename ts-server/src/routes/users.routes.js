import express from 'express';

import { hashPassword } from '../lib/password.js';

import {

  canActorAssignRole,

  canActorManageTarget,

  canCreateUsers,

  canListUsers,

  createAuthMiddleware,

  normRole,

} from '../middleware/user_permissions.js';



export function createUsersRouter(pool) {

  const r = express.Router();

  const auth = createAuthMiddleware(pool);



  r.use(auth);

  /**
   * SĐT nhân sự để gọi (KH, CSKH, …) — gộp staff_db (workshop-data) + users.phone trên server.
   * Không trả mật khẩu; chỉ username, phone, name, role.
   */
  r.get('/dial-contacts', async (req, res) => {
    try {
      const actor = normRole(req.user.role);
      const byUser = new Map();

      const scopeId = req.user.xdv_id ? String(req.user.xdv_id) : 'global';
      const blob = await pool.query(
        `SELECT payload FROM workshop_data_blobs WHERE scope_id = $1 AND data_key = 'staff_db'`,
        [scopeId],
      );
      if (blob.rowCount > 0) {
        const payload = blob.rows[0].payload;
        const list = Array.isArray(payload) ? payload : [];
        for (const row of list) {
          if (row && row.isActive === false) continue;
          const username = String(row.username || '').trim();
          const phone = String(row.phone || '').trim();
          if (!username || !phone) continue;
          byUser.set(username.toLowerCase(), {
            username,
            phone,
            name: String(row.fullName || row.name || username).trim(),
            role: String(row.role || '').trim(),
          });
        }
      }

      const vals = [];
      let scopeExtra = '';
      if (actor !== 'ADMIN') {
        vals.push(req.user.xdv_id ?? null);
        scopeExtra = ` AND u.xdv_id IS NOT DISTINCT FROM $${vals.length}`;
      }
      const users = await pool.query(
        `
        SELECT u.username, u.name, u.role, u.phone
        FROM users u
        WHERE u.is_active = true
          AND u.phone IS NOT NULL
          AND trim(u.phone) <> ''
          ${scopeExtra}
        `,
        vals,
      );
      for (const row of users.rows) {
        const username = String(row.username || '').trim();
        const phone = String(row.phone || '').trim();
        if (!username || !phone) continue;
        byUser.set(username.toLowerCase(), {
          username,
          phone,
          name: String(row.name || username).trim(),
          role: String(row.role || '').trim(),
        });
      }

      res.json([...byUser.values()]);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  /** Quản đốc / Giám đốc / Admin — danh sách KTV đang hoạt động để phân công. */
  r.get('/assignable-ktv', async (req, res) => {
    const actor = normRole(req.user.role);
    if (!['ADMIN', 'GIAMDOC', 'QUANDOC'].includes(actor)) {
      return res.status(403).json({ error: 'Không có quyền xem danh sách KTV.' });
    }
    try {
      const isGiamDoc = actor === 'GIAMDOC';
      const vals = [];
      let extra = '';
      if (isGiamDoc) {
        vals.push(req.user.xdv_id ?? null);
        extra = ` AND u.xdv_id IS NOT DISTINCT FROM $${vals.length}`;
      }
      const result = await pool.query(
        `
        SELECT u.id, u.username, u.name, u.role, u.is_active, u.created_at, u.xdv_id, u.last_login_at, u.phone
        FROM users u
        WHERE upper(trim(replace(u.role, ' ', '_'))) = 'KTV' AND u.is_active = true
        ${extra}
        ORDER BY u.name, u.username
        `,
        vals,
      );
      res.json(result.rows);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  /** CSKH / Giám đốc / Admin — danh sách CVDV đang hoạt động để phân công xe. */
  r.get('/assignable-cvdv', async (req, res) => {
    const actor = normRole(req.user.role);
    if (!['ADMIN', 'GIAMDOC', 'CSKH'].includes(actor)) {
      return res.status(403).json({ error: 'Không có quyền xem danh sách CVDV.' });
    }
    try {
      const vals = [];
      let scopeExtra = '';
      if (actor === 'GIAMDOC' || actor === 'CSKH') {
        vals.push(req.user.xdv_id ?? null);
        scopeExtra = ` AND u.xdv_id IS NOT DISTINCT FROM $${vals.length}`;
      }
      const result = await pool.query(
        `
        SELECT u.id, u.username, u.name, u.role, u.is_active, u.created_at, u.xdv_id, u.last_login_at, u.phone
        FROM users u
        WHERE u.is_active = true
          AND (
            upper(trim(replace(replace(replace(u.role, ' ', '_'), 'Ố', 'O'), 'Ấ', 'A'))) IN ('CVDV', 'CO_VAN', 'COVAN')
            OR upper(u.role) LIKE '%CVDV%'
            OR upper(u.role) LIKE '%CỐ VẤN%'
            OR upper(u.role) LIKE '%CO VAN%'
          )
          ${scopeExtra}
        ORDER BY u.name, u.username
        `,
        vals,
      );
      res.json(result.rows);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  r.get('/', async (req, res) => {

    if (!canListUsers(req.user.role)) {

      return res.status(403).json({ error: 'Bạn không có quyền xem danh sách tài khoản.' });

    }

    try {

      const isGiamDoc = normRole(req.user.role) === 'GIAMDOC';
      const vals = [];
      const where = [];
      if (isGiamDoc) {
        where.push(`upper(trim(replace(u.role, ' ', '_'))) NOT IN ('ADMIN', 'GIAMDOC')`);
        vals.push(req.user.xdv_id ?? null);
        where.push(`u.xdv_id IS NOT DISTINCT FROM $${vals.length}`);
      }

      const result = await pool.query(

        `

        SELECT u.id, u.username, u.name, u.role, u.is_active, u.created_at, u.xdv_id, u.last_login_at, u.phone, x.name AS xdv_name

        FROM users u

        LEFT JOIN xdvs x ON u.xdv_id = x.id

        ${where.length ? `WHERE ${where.join(' AND ')}` : ''}

        ORDER BY u.created_at DESC

      `,

        vals,

      );

      res.json(result.rows);

    } catch (err) {

      res.status(500).json({ error: err.message });

    }

  });



  r.post('/', async (req, res) => {

    if (!canCreateUsers(req.user.role)) {

      return res.status(403).json({ error: 'Bạn không có quyền tạo tài khoản.' });

    }

    const { username, password, name, role, xdv_id, phone } = req.body || {};

    if (!username || !password || !name || !role) {

      return res.status(400).json({ error: 'Thiếu username, password, name hoặc role' });

    }

    if (!canActorAssignRole(req.user.role, role)) {

      return res.status(403).json({

        error: 'Bạn không được phép tạo tài khoản với vai trò này (chỉ Quản trị ADMIN mới quản lý ADMIN / Giám đốc).',

      });

    }

    try {

      const finalXdvId = xdv_id && xdv_id !== '' ? xdv_id : null;

      const ph = await hashPassword(String(password));

      const phoneVal = phone != null && String(phone).trim() !== '' ? String(phone).trim() : null;

      const result = await pool.query(

        `INSERT INTO users (username, password, password_hash, name, role, xdv_id, phone)

         VALUES ($1, '', $2, $3, $4, $5, $6)

         RETURNING id, username, name, role, xdv_id, phone`,

        [username, ph, name, role, finalXdvId, phoneVal],

      );

      res.status(201).json(result.rows[0]);

    } catch (err) {

      if (err.code === '23505') res.status(400).json({ error: 'Tên đăng nhập đã tồn tại!' });

      else res.status(500).json({ error: err.message });

    }

  });



  r.patch('/:id', async (req, res) => {

    const { id } = req.params;

    const { name, role, xdv_id, password, phone } = req.body || {};

    try {

      const existing = await pool.query(`SELECT id, role FROM users WHERE id = $1`, [id]);

      if (existing.rowCount === 0) return res.status(404).json({ error: 'Không tìm thấy user' });

      const targetRole = existing.rows[0].role;

      if (!canActorManageTarget(req.user.role, targetRole)) {

        return res.status(403).json({

          error: 'Không được sửa tài khoản Quản trị (ADMIN) hoặc Giám đốc khác — liên hệ ADMIN.',

        });

      }

      if (role !== undefined && !canActorAssignRole(req.user.role, role)) {

        return res.status(403).json({ error: 'Bạn không được gán vai trò này.' });

      }

      const fields = [];

      const vals = [];

      let n = 1;

      if (name !== undefined) {

        fields.push(`name = $${n++}`);

        vals.push(name);

      }

      if (role !== undefined) {

        fields.push(`role = $${n++}`);

        vals.push(role);

      }

      if (xdv_id !== undefined) {

        fields.push(`xdv_id = $${n++}`);

        vals.push(xdv_id && xdv_id !== '' ? xdv_id : null);

      }

      if (phone !== undefined) {

        fields.push(`phone = $${n++}`);

        vals.push(phone != null && String(phone).trim() !== '' ? String(phone).trim() : null);

      }

      if (password !== undefined && String(password) !== '') {

        const ph = await hashPassword(String(password));

        fields.push(`password = ''`);

        fields.push(`password_hash = $${n++}`);

        vals.push(ph);

      }

      if (fields.length === 0) return res.status(400).json({ error: 'Không có trường cập nhật' });

      vals.push(id);

      const result = await pool.query(

        `UPDATE users SET ${fields.join(', ')} WHERE id = $${n} RETURNING id, username, name, role, xdv_id, phone`,

        vals,

      );

      res.json(result.rows[0]);

    } catch (err) {

      res.status(500).json({ error: err.message });

    }

  });



  r.delete('/:id', async (req, res) => {

    const { id } = req.params;

    try {

      const existing = await pool.query(`SELECT id, role, is_active FROM users WHERE id = $1`, [id]);

      if (existing.rowCount === 0) return res.status(404).json({ error: 'Không tìm thấy user' });

      if (String(existing.rows[0].id) === String(req.user.id)) {

        return res.status(403).json({ error: 'Không thể tự khóa tài khoản của chính bạn.' });

      }

      if (!canActorManageTarget(req.user.role, existing.rows[0].role)) {

        return res.status(403).json({

          error: 'Không được khóa/mở tài khoản ADMIN hoặc Giám đốc — liên hệ Quản trị.',

        });

      }

      const newStatus = !existing.rows[0].is_active;

      await pool.query(`UPDATE users SET is_active = $1 WHERE id = $2`, [newStatus, id]);

      res.json({ message: newStatus ? 'Đã mở khóa tài khoản' : 'Đã khóa tài khoản' });

    } catch (err) {

      res.status(500).json({ error: err.message });

    }

  });



  return r;

}

