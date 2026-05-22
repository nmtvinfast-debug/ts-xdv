import express from 'express';
import { createAuthMiddleware, normRole } from '../middleware/user_permissions.js';
import { khAdsBannerMode, mergeWorkshopDefaults, resolveKhAdRates } from '../lib/kh_ads_config.js';
import { mustFilterByWorkshop, sqlWorkshopMatch } from '../lib/workshop_scope.js';

const STAFF_ROLES = new Set([
  'ADMIN',
  'GIAMDOC',
  'CSKH',
  'CVDV',
  'QUANDOC',
  'KTV',
  'KHO',
  'KETOAN',
  'BAOVE',
  'TV',
  'TIVI',
]);

function roleLabelVi(role) {
  const r = normRole(role);
  const map = {
    ADMIN: 'Quản trị',
    GIAMDOC: 'Giám đốc',
    CSKH: 'CSKH',
    CVDV: 'CVDV',
    QUANDOC: 'Quản đốc',
    KTV: 'KTV',
    KHO: 'Kho',
    KETOAN: 'Kế toán',
    BAOVE: 'Bảo vệ',
    TV: 'TV',
    TIVI: 'TV',
    KHACHHANG: 'Khách hàng',
  };
  return map[r] || role;
}

async function loadWorkshopMerged(pool) {
  const result = await pool.query(`SELECT workshop_defaults FROM app_settings WHERE id = 1`);
  const stored = result.rows[0]?.workshop_defaults;
  return mergeWorkshopDefaults(typeof stored === 'object' && stored ? stored : {});
}

async function ensureCompanyChatSchema(pool) {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS company_messages (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        sender_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
        sender_name VARCHAR(255) NOT NULL DEFAULT '',
        sender_role VARCHAR(50) NOT NULL DEFAULT '',
        body TEXT NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );
  `);
  await pool.query(`
    ALTER TABLE company_messages
    ADD COLUMN IF NOT EXISTS xdv_id UUID REFERENCES xdvs(id) ON DELETE SET NULL;
  `);
  await pool.query(`
    UPDATE company_messages m
    SET xdv_id = u.xdv_id
    FROM users u
    WHERE m.sender_user_id = u.id AND m.xdv_id IS NULL
  `);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS company_chat_read_state (
        user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
        last_read_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
    );
  `);
}

function chatScopeSql(user, alias, startIdx) {
  const scope = sqlWorkshopMatch(alias, user, startIdx);
  return scope;
}

export function createCompanyChatRouter(pool) {
  const r = express.Router();
  const auth = createAuthMiddleware(pool);

  r.use(auth);
  r.use(async (req, res, next) => {
    try {
      await ensureCompanyChatSchema(pool);
      next();
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  r.get('/messages/unread-count', async (req, res) => {
    const role = normRole(req.user.role);
    if (!STAFF_ROLES.has(role)) {
      return res.status(403).json({ error: 'Không có quyền xem chat công ty.' });
    }
    try {
      const scope = chatScopeSql(req.user, 'm', 2);
      const vals = [req.user.id];
      if (scope.value !== undefined) vals.push(scope.value);
      const result = await pool.query(
        `
        SELECT COUNT(*)::int AS unread
        FROM company_messages m
        WHERE m.created_at > COALESCE(
          (SELECT last_read_at FROM company_chat_read_state WHERE user_id = $1),
          '1970-01-01'::timestamptz
        )
        AND (m.sender_user_id IS NULL OR m.sender_user_id <> $1)
        ${scope.clause}
        `,
        vals,
      );
      res.json({ unread: result.rows[0]?.unread ?? 0 });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  r.post('/messages/mark-read', async (req, res) => {
    const role = normRole(req.user.role);
    if (!STAFF_ROLES.has(role)) {
      return res.status(403).json({ error: 'Không có quyền xem chat công ty.' });
    }
    try {
      await pool.query(
        `
        INSERT INTO company_chat_read_state (user_id, last_read_at)
        VALUES ($1, NOW())
        ON CONFLICT (user_id) DO UPDATE SET last_read_at = NOW()
        `,
        [req.user.id],
      );
      res.json({ ok: true, unread: 0 });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  r.get('/messages', async (req, res) => {
    const role = normRole(req.user.role);
    if (!STAFF_ROLES.has(role)) {
      return res.status(403).json({ error: 'Không có quyền xem chat công ty.' });
    }
    const limit = Math.min(300, Math.max(1, parseInt(req.query.limit, 10) || 150));
    const since = req.query.since;
    try {
      const scope = chatScopeSql(req.user, '', 1);
      let sql = `
        SELECT id, sender_user_id, sender_name, sender_role, body, created_at, xdv_id
        FROM company_messages
      `;
      const vals = [];
      const where = [];
      if (since) {
        vals.push(since);
        where.push(`created_at > $${vals.length}::timestamptz`);
      }
      if (scope.value !== undefined) {
        vals.push(scope.value);
        where.push(`xdv_id IS NOT DISTINCT FROM $${vals.length}`);
      }
      if (where.length) sql += ` WHERE ${where.join(' AND ')}`;
      vals.push(limit);
      sql += ` ORDER BY created_at ASC LIMIT $${vals.length}`;
      const result = await pool.query(sql, vals);
      res.json({ messages: result.rows });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  r.post('/messages', async (req, res) => {
    const role = normRole(req.user.role);
    if (!STAFF_ROLES.has(role)) {
      return res.status(403).json({ error: 'Không có quyền gửi chat công ty.' });
    }
    const body = String(req.body?.body ?? req.body?.message ?? '').trim();
    if (!body) return res.status(400).json({ error: 'Nội dung tin nhắn trống.' });
    if (body.length > 4000) return res.status(400).json({ error: 'Tin nhắn quá dài (tối đa 4000 ký tự).' });
    try {
      const name = req.user.name || req.user.username || 'N/A';
      const workshopId = req.user.xdv_id ?? null;
      const result = await pool.query(
        `INSERT INTO company_messages (sender_user_id, sender_name, sender_role, body, xdv_id)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING id, sender_user_id, sender_name, sender_role, body, created_at, xdv_id`,
        [req.user.id, name, normRole(req.user.role), body, workshopId],
      );
      res.status(201).json({
        message: result.rows[0],
        role_label: roleLabelVi(role),
      });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  /** Lượt xem — ghi doanh thu theo đơn giá VND/lượt xem. */
  r.post('/kh-ads/impression', async (req, res) => {
    const role = normRole(req.user.role);
    if (role !== 'KHACHHANG') {
      return res.status(403).json({ error: 'Chỉ tài khoản Khách hàng ghi nhận lượt xem quảng cáo.' });
    }
    const adId = String(req.body?.ad_id ?? '').trim();
    if (!adId) return res.status(400).json({ error: 'Thiếu ad_id' });
    try {
      const merged = await loadWorkshopMerged(pool);
      if (!khAdsBannerMode(merged)) {
        return res.status(403).json({ error: 'Quảng cáo banner đang tắt.' });
      }
      const { vndPerView } = resolveKhAdRates(adId, merged);
      const result = await pool.query(
        `INSERT INTO kh_ad_impressions (ad_id, user_id, revenue_vnd)
         VALUES ($1, $2, $3)
         RETURNING id, revenue_vnd`,
        [adId.slice(0, 64), req.user.id, vndPerView],
      );
      res.json({
        ok: true,
        event: 'view',
        ad_id: adId,
        revenue_vnd: Number(result.rows[0]?.revenue_vnd ?? vndPerView),
      });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  /** Lượt click — ghi doanh thu theo đơn giá VND/lượt click. */
  r.post('/kh-ads/click', async (req, res) => {
    const role = normRole(req.user.role);
    if (role !== 'KHACHHANG') {
      return res.status(403).json({ error: 'Chỉ tài khoản Khách hàng ghi nhận lượt click quảng cáo.' });
    }
    const adId = String(req.body?.ad_id ?? '').trim();
    if (!adId) return res.status(400).json({ error: 'Thiếu ad_id' });
    try {
      const merged = await loadWorkshopMerged(pool);
      if (!khAdsBannerMode(merged)) {
        return res.status(403).json({ error: 'Quảng cáo banner đang tắt.' });
      }
      const { vndPerClick } = resolveKhAdRates(adId, merged);
      const result = await pool.query(
        `INSERT INTO kh_ad_clicks (ad_id, user_id, revenue_vnd)
         VALUES ($1, $2, $3)
         RETURNING id, revenue_vnd`,
        [adId.slice(0, 64), req.user.id, vndPerClick],
      );
      res.json({
        ok: true,
        event: 'click',
        ad_id: adId,
        revenue_vnd: Number(result.rows[0]?.revenue_vnd ?? vndPerClick),
      });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  r.get('/kh-ads/stats', async (req, res) => {
    if (normRole(req.user.role) !== 'ADMIN') {
      return res.status(403).json({ error: 'Chỉ ADMIN xem thống kê quảng cáo.' });
    }
    try {
      const merged = await loadWorkshopMerged(pool);
      const viewsQ = await pool.query(`
        SELECT ad_id,
               COUNT(*)::int AS views,
               COALESCE(SUM(revenue_vnd), 0)::float AS revenue_views_vnd
        FROM kh_ad_impressions
        GROUP BY ad_id
      `);
      const clicksQ = await pool.query(`
        SELECT ad_id,
               COUNT(*)::int AS clicks,
               COALESCE(SUM(revenue_vnd), 0)::float AS revenue_clicks_vnd
        FROM kh_ad_clicks
        GROUP BY ad_id
      `);
      const byAd = new Map();
      for (const row of viewsQ.rows) {
        byAd.set(row.ad_id, {
          ad_id: row.ad_id,
          views: row.views,
          clicks: 0,
          revenue_views_vnd: Number(row.revenue_views_vnd) || 0,
          revenue_clicks_vnd: 0,
        });
      }
      for (const row of clicksQ.rows) {
        const cur = byAd.get(row.ad_id) || {
          ad_id: row.ad_id,
          views: 0,
          clicks: 0,
          revenue_views_vnd: 0,
          revenue_clicks_vnd: 0,
        };
        cur.clicks = row.clicks;
        cur.revenue_clicks_vnd = Number(row.revenue_clicks_vnd) || 0;
        byAd.set(row.ad_id, cur);
      }
      const stats = [...byAd.values()]
        .map((s) => ({
          ...s,
          revenue_total_vnd: s.revenue_views_vnd + s.revenue_clicks_vnd,
        }))
        .sort((a, b) => b.revenue_total_vnd - a.revenue_total_vnd);

      const summary = stats.reduce(
        (acc, s) => {
          acc.views += s.views;
          acc.clicks += s.clicks;
          acc.revenue_views_vnd += s.revenue_views_vnd;
          acc.revenue_clicks_vnd += s.revenue_clicks_vnd;
          acc.revenue_total_vnd += s.revenue_total_vnd;
          return acc;
        },
        {
          views: 0,
          clicks: 0,
          revenue_views_vnd: 0,
          revenue_clicks_vnd: 0,
          revenue_total_vnd: 0,
        },
      );

      res.json({
        stats,
        summary,
        rates: merged.kh_ads_revenue,
      });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  return r;
}
