import express from 'express';

export function createBookingsRouter(pool) {
  const r = express.Router();

  r.get('/', async (req, res) => {
    try {
      const result = await pool.query('SELECT * FROM bookings ORDER BY created_at DESC');
      res.json(result.rows);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  r.post('/', async (req, res) => {
    const { customer_name, customer_phone, car_model, bien_so, time, note, status } = req.body || {};
    try {
      const result = await pool.query(
        `INSERT INTO bookings (customer_name, customer_phone, car_model, bien_so, time, note, status)
         VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
        [customer_name, customer_phone, car_model, bien_so, time, note, status],
      );
      res.status(201).json(result.rows[0]);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  r.delete('/:id', async (req, res) => {
    try {
      await pool.query(`DELETE FROM bookings WHERE id = $1`, [req.params.id]);
      res.json({ message: 'Đã xóa lịch hẹn' });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  return r;
}
