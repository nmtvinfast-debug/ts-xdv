import { normRole } from '../middleware/user_permissions.js';

/** Quản trị hệ thống — không thuộc một xưởng, được xem dữ liệu toàn hệ thống (quản trị). */
export function isSystemAdmin(user) {
  return normRole(user?.role) === 'ADMIN';
}

/**
 * Phạm vi xưởng cho nhân viên (GIAMDOC, CVDV, …).
 * null = chỉ bản ghi không gán xưởng (xdv_id IS NULL).
 */
export function workshopIdForActor(user) {
  if (isSystemAdmin(user)) return undefined;
  return user?.xdv_id ?? null;
}

/** true nếu cần lọc theo xdv_id (mọi role trừ ADMIN). */
export function mustFilterByWorkshop(user) {
  return !isSystemAdmin(user);
}

/**
 * Điều kiện SQL: `alias.xdv_id IS NOT DISTINCT FROM $n`
 * Trả về { clause, value } hoặc { clause: '', value: undefined } nếu không lọc.
 */
export function sqlWorkshopMatch(alias, user, paramIndex = 1) {
  if (!mustFilterByWorkshop(user)) {
    return { clause: '', value: undefined, paramIndex };
  }
  const col = alias ? `${alias}.xdv_id` : 'xdv_id';
  return {
    clause: ` AND ${col} IS NOT DISTINCT FROM $${paramIndex}`,
    value: workshopIdForActor(user),
    paramIndex: paramIndex + 1,
  };
}
