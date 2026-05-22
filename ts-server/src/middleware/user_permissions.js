import { parseBearerActor } from '../lib/ro_time_rules.js';

export function normRole(role) {
  const upper = String(role || '')
    .trim()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toUpperCase()
    .replace(/[\s\-]+/g, '_');
  const aliases = {
    KE_TOAN: 'KETOAN',
    GIAM_DOC: 'GIAMDOC',
    BAO_VE: 'BAOVE',
    QUAN_DOC: 'QUANDOC',
    KY_THUAT: 'KTV',
    CO_VAN: 'CVDV',
    KHACH_HANG: 'KHACHHANG',
    TIVI: 'TV',
    QUAN_TRI: 'ADMIN',
    QUANTRI: 'ADMIN',
    QUAN_LY: 'ADMIN',
    QUANLY: 'ADMIN',
  };
  return aliases[upper] || upper;
}

/** Vai trò Giám đốc xưởng được tạo / sửa (không gồm ADMIN, GIAMDOC). */
export const ROLES_GIAMDOC_MANAGES = new Set([
  'CVDV',
  'KETOAN',
  'KTV',
  'QUANDOC',
  'KHO',
  'BAOVE',
  'CSKH',
  'TV',
]);

export function createAuthMiddleware(pool) {
  return async function authUser(req, res, next) {
    const actor = parseBearerActor(req);
    if (!actor?.user_id && !actor?.username) {
      return res.status(401).json({ error: 'Chưa đăng nhập' });
    }
    try {
      const result = actor.user_id
        ? await pool.query(
            `SELECT id, username, name, role, is_active, xdv_id FROM users WHERE id = $1`,
            [actor.user_id],
          )
        : await pool.query(
            `SELECT id, username, name, role, is_active, xdv_id FROM users WHERE LOWER(username) = LOWER($1)`,
            [actor.username],
          );
      if (result.rowCount === 0) {
        const hint = actor.username
          ? 'Tài khoản nội bộ (staff_db) chưa có trên máy chủ — dùng đăng nhập API hoặc tạo user trên server.'
          : 'Phiên đăng nhập không hợp lệ — đăng xuất và đăng nhập lại.';
        return res.status(401).json({ error: hint });
      }
      const row = result.rows[0];
      if (!row.is_active) {
        return res.status(403).json({ error: 'Tài khoản của bạn đang bị khóa' });
      }
      req.user = row;
      next();
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  };
}

export function canListUsers(actorRole) {
  const r = normRole(actorRole);
  return r === 'ADMIN' || r === 'GIAMDOC';
}

export function canActorAssignRole(actorRole, newRole) {
  const a = normRole(actorRole);
  const t = normRole(newRole);
  if (a === 'ADMIN') return t.length > 0;
  if (a === 'GIAMDOC') return ROLES_GIAMDOC_MANAGES.has(t);
  return false;
}

/** Sửa / khóa tài khoản đích. */
export function canActorManageTarget(actorRole, targetRole) {
  const a = normRole(actorRole);
  const t = normRole(targetRole);
  if (a === 'ADMIN') return true;
  if (a === 'GIAMDOC') {
    if (t === 'ADMIN' || t === 'GIAMDOC') return false;
    return ROLES_GIAMDOC_MANAGES.has(t);
  }
  return false;
}

export function canCreateUsers(actorRole) {
  const r = normRole(actorRole);
  return r === 'ADMIN' || r === 'GIAMDOC';
}
