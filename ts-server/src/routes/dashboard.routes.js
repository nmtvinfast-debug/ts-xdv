import express from 'express';

export function createDashboardRouter(pool) {
  const r = express.Router();

  r.get('/summary', async (req, res) => {
    try {
      const [xdv, users, roOpen, roPay, inWorkshop] = await Promise.all([
        pool.query(`SELECT COUNT(*)::int AS c FROM xdvs WHERE status = 'Hoạt động'`),
        pool.query(`SELECT COUNT(*)::int AS c FROM users WHERE is_active = TRUE`),
        pool.query(
          `SELECT COUNT(*)::int AS c FROM repair_orders WHERE status NOT IN ('XE_RA_XUONG','DA_RA_CONG','DA_RA_CONG_THIEU_PT')`,
        ),
        pool.query(`SELECT COUNT(*)::int AS c FROM repair_orders WHERE status = 'CHO_QUYET_TOAN'`),
        pool.query(
          `SELECT COUNT(*)::int AS c FROM repair_orders WHERE status NOT IN ('XE_RA_XUONG','DA_RA_CONG','DA_RA_CONG_THIEU_PT') AND time_out IS NULL`,
        ),
      ]);

      const byStatus = await pool.query(
        `SELECT status, COUNT(*)::int AS c FROM repair_orders GROUP BY status`,
      );

      res.json({
        xdvs_active: xdv.rows[0]?.c ?? 0,
        users_active: users.rows[0]?.c ?? 0,
        repair_orders_open: roOpen.rows[0]?.c ?? 0,
        repair_orders_in_workshop: inWorkshop.rows[0]?.c ?? 0,
        repair_orders_cho_quyet_toan: roPay.rows[0]?.c ?? 0,
        repair_orders_by_status: Object.fromEntries(byStatus.rows.map((x) => [x.status, x.c])),
      });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  return r;
}
