/**
 * Quản đốc nghiệm thu xong → báo CVDV phụ trách (chốt hồ sơ / chuyển Kế toán / giao xe).
 */
export async function tryNotifyCvdvQuanDocApproved(db, row, { fromStatus } = {}) {
  const cvdv = String(row.cvdv_username || '').trim();
  if (!cvdv) return { notified: false, reason: 'no_cvdv' };

  const cres = await db.query(
    `SELECT id FROM users
     WHERE LOWER(TRIM(username)) = $1 AND COALESCE(is_active, true) = true
     LIMIT 1`,
    [cvdv.toLowerCase()],
  );
  if (cres.rowCount === 0) return { notified: false, reason: 'cvdv_user_not_found' };

  const cvdvId = cres.rows[0].id;
  const roId = row.id;
  const dup = await db.query(
    `SELECT id FROM notifications
     WHERE user_id = $1
       AND (data->>'type') = 'QD_INSPECTION_DONE_FOR_CVDV'
       AND (data->>'repair_order_id') = $2
       AND created_at > NOW() - INTERVAL '7 days'
     LIMIT 1`,
    [cvdvId, roId],
  );
  if (dup.rowCount > 0) return { notified: false, reason: 'duplicate' };

  const bien = String(row.bien_so || '').trim();
  const roCode = String(row.ro_code || '').trim();
  const ktv = String(row.ktv_username || '').trim();
  const title = `QD nghiệm thu xong — ${bien || roCode}`;
  const body =
    `RO ${roCode}: Quản đốc đã nghiệm thu sửa chữa${ktv ? ` (KTV: ${ktv})` : ''}. ` +
    `Xe chờ CVDV chốt hồ sơ, chuyển Kế toán và phối hợp giao xe.`;

  await db.query(`INSERT INTO notifications (user_id, title, body, data) VALUES ($1, $2, $3, $4::jsonb)`, [
    cvdvId,
    title,
    body,
    JSON.stringify({
      type: 'QD_INSPECTION_DONE_FOR_CVDV',
      repair_order_id: roId,
      bien_so: bien,
      ro_code: roCode,
      from_status: fromStatus || null,
    }),
  ]);

  return { notified: true, user_id: cvdvId };
}
