import express from 'express';

export function createXdvsRouter(pool) {
  const r = express.Router();

  r.get('/', async (req, res) => {
    try {
      const result = await pool.query('SELECT * FROM xdvs ORDER BY created_at DESC');
      res.json(result.rows);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  r.post('/', async (req, res) => {
    const { code, name, address, phone, email } = req.body || {};
    try {
      const result = await pool.query(
        `INSERT INTO xdvs (code, name, address, phone, email) VALUES ($1, $2, $3, $4, $5) RETURNING *`,
        [code, name, address, phone, email],
      );
      res.status(201).json(result.rows[0]);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  r.patch('/:id', async (req, res) => {
    const { id } = req.params;
    const { name, address, phone } = req.body || {};
    try {
      const result = await pool.query(
        `UPDATE xdvs SET name = COALESCE($1, name), address = COALESCE($2, address), phone = COALESCE($3, phone) WHERE id = $4 RETURNING *`,
        [name, address, phone, id],
      );
      res.json(result.rows[0]);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  r.delete('/:id', async (req, res) => {
    const { id } = req.params;
    try {
      const current = await pool.query(`SELECT status FROM xdvs WHERE id = $1`, [id]);
      if (current.rowCount === 0) return res.status(404).json({ error: 'Không tìm thấy XDV' });
      const newStatus = current.rows[0].status === 'Hoạt động' ? 'Tạm khóa' : 'Hoạt động';
      await pool.query(`UPDATE xdvs SET status = $1 WHERE id = $2`, [newStatus, id]);
      res.json({ message: `Đã chuyển trạng thái thành: ${newStatus}` });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  return r;
}
