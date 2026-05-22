const express = require('express');
const bcrypt = require('bcryptjs');

function createUsersRouter(db) {
  const router = express.Router();

  router.get('/', async (req, res) => {
    try {
      const { rows } = await db.query(
        `
        SELECT id, username, full_name, role, phone, workshop_id, branch_id, is_active
        FROM users
        ORDER BY username ASC
        `
      );
      res.json({ ok: true, items: rows });
    } catch (e) {
      res.status(500).json({ ok: false, error: e.message });
    }
  });

  router.post('/', async (req, res) => {
    try {
      const body = req.body || {};
      if (!body.username || !body.password || !body.role) {
        return res.status(400).json({ ok: false, error: 'Thiếu username/password/role.' });
      }
      const exists = await db.query(`SELECT id FROM users WHERE username = $1 LIMIT 1`, [body.username]);
      if (exists.rowCount > 0) {
        return res.status(400).json({ ok: false, error: 'Username đã tồn tại.' });
      }
      const passwordHash = await bcrypt.hash(body.password, 10);
      const { rows } = await db.query(
        `
        INSERT INTO users(username, password_hash, full_name, role, phone, workshop_id, branch_id, is_active)
        VALUES ($1,$2,$3,$4,$5,$6,$7,COALESCE($8, TRUE))
        RETURNING id, username, full_name, role, phone, workshop_id, branch_id, is_active
        `,
        [
          body.username,
          passwordHash,
          body.full_name || null,
          body.role,
          body.phone || null,
          body.workshop_id || null,
          body.branch_id || null,
          typeof body.is_active === 'boolean' ? body.is_active : true,
        ]
      );
      res.status(201).json({ ok: true, item: rows[0] });
    } catch (e) {
      res.status(500).json({ ok: false, error: e.message });
    }
  });

  router.put('/:id', async (req, res) => {
    try {
      const body = req.body || {};
      let passwordClause = '';
      const params = [
        req.params.id,
        body.full_name ?? null,
        body.role ?? null,
        body.phone ?? null,
        body.workshop_id ?? null,
        body.branch_id ?? null,
        typeof body.is_active === 'boolean' ? body.is_active : null,
      ];

      if (body.password) {
        const passwordHash = await bcrypt.hash(body.password, 10);
        params.push(passwordHash);
        passwordClause = `, password_hash = $8`;
      }

      const sql = `
        UPDATE users
        SET
          full_name = COALESCE($2, full_name),
          role = COALESCE($3, role),
          phone = COALESCE($4, phone),
          workshop_id = COALESCE($5, workshop_id),
          branch_id = COALESCE($6, branch_id),
          is_active = COALESCE($7, is_active)
          ${passwordClause},
          updated_at = NOW()
        WHERE id = $1
        RETURNING id, username, full_name, role, phone, workshop_id, branch_id, is_active
      `;
      const { rows, rowCount } = await db.query(sql, params);
      if (!rowCount) {
        return res.status(404).json({ ok: false, error: 'Không tìm thấy user.' });
      }
      res.json({ ok: true, item: rows[0] });
    } catch (e) {
      res.status(500).json({ ok: false, error: e.message });
    }
  });

  return router;
}

module.exports = { createUsersRouter };
