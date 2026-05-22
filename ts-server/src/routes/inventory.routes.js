import express from 'express';

export function createInventoryRouter(pool) {
  const r = express.Router();

  r.get('/items', async (req, res) => {
    const xdvId = req.query.xdv_id || null;
    try {
      const result = xdvId
        ? await pool.query(
            `SELECT * FROM inventory_items WHERE xdv_id = $1 OR xdv_id IS NULL ORDER BY part_code`,
            [xdvId],
          )
        : await pool.query(`SELECT * FROM inventory_items ORDER BY part_code`);
      res.json(result.rows);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  r.post('/items', async (req, res) => {
    const { xdv_id, part_code, name, quantity, unit, price_in, price_out, location } = req.body || {};
    if (!part_code || !name) return res.status(400).json({ error: 'Thiếu part_code hoặc name' });
    try {
      const result = await pool.query(
        `INSERT INTO inventory_items (xdv_id, part_code, name, quantity, unit, price_in, price_out, location)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`,
        [
          xdv_id || null,
          String(part_code),
          String(name),
          Number(quantity) || 0,
          unit || '',
          price_in ?? null,
          price_out ?? null,
          location || null,
        ],
      );
      res.status(201).json(result.rows[0]);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  return r;
}
