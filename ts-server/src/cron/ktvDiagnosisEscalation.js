import cron from 'node-cron';

/** Trạng thái KTV còn trong giai đoạn kiểm tra / sửa (chưa nghiệm thu QĐ). */
const KTV_DIAGNOSIS_STATUSES = ['CHO_PHAN_CONG', 'CHO_SUA_CHUA', 'DANG_SUA', 'DUNG_SUA', 'CHO_PHU_TUNG'];

function normRole(role) {
  return String(role || '')
    .toUpperCase()
    .replace(/\s/g, '')
    .replace(/Ố/g, 'O')
    .replace(/Ấ/g, 'A');
}

/**
 * Xe đã giao KTV ≥ N giờ mà chưa ghi nhận fault_diagnosis_at → thông báo Quản đốc (QUANDOC).
 * Tránh spam: tối đa 1 bản ghi / RO / 24h (type KTV_DIAGNOSIS_OVERDUE).
 */
export async function runKtvDiagnosisEscalationOnce(pool) {
  const hours = Math.max(1, Number(process.env.KTV_DIAGNOSIS_SLA_HOURS || 4));
  const dedupeHours = Math.max(1, Number(process.env.KTV_DIAGNOSIS_NOTIFY_DEDUPE_HOURS || 24));

  const owners = await pool.query(
    `SELECT id, role FROM users
     WHERE COALESCE(is_active, true) = true
       AND TRIM(username) <> ''`,
  );
  let quanDocIds = owners.rows.filter((r) => normRole(r.role) === 'QUANDOC').map((r) => r.id);

  if (quanDocIds.length === 0) {
    console.warn('[ktv-diagnosis] Không có user role QUANDOC — thử gửi cho GIAMDOC.');
    quanDocIds.push(...owners.rows.filter((r) => normRole(r.role) === 'GIAMDOC').map((r) => r.id));
  }
  if (quanDocIds.length === 0) return { checked: 0, notified: 0 };

  const roRes = await pool.query(
    `SELECT *
     FROM repair_orders ro
     WHERE TRIM(COALESCE(ro.ktv_username, '')) <> ''
       AND ro.fault_diagnosis_at IS NULL
       AND ro.status = ANY($1::text[])
       AND COALESCE(ro.time_start, ro.time_assign, ro.last_status_changed_at, ro.time_in) IS NOT NULL
       AND COALESCE(ro.time_start, ro.time_assign, ro.last_status_changed_at, ro.time_in)
           <= NOW() - ($2::numeric * INTERVAL '1 hour')
       AND NOT EXISTS (
         SELECT 1 FROM notifications n
         WHERE (n.data->>'type') = 'KTV_DIAGNOSIS_OVERDUE'
           AND (n.data->>'repair_order_id') = ro.id::text
           AND n.created_at > NOW() - ($3::numeric * INTERVAL '1 hour')
       )`,
    [KTV_DIAGNOSIS_STATUSES, hours, dedupeHours],
  );

  let notified = 0;
  for (const row of roRes.rows) {
    const bien = String(row.bien_so || '').trim();
    const roCode = String(row.ro_code || '').trim();
    const ktv = String(row.ktv_username || '').trim();
    const title = `KTV kiểm tra quá ${hours}h — chưa xác nhận nguyên nhân`;
    const body = `Xe ${bien || roCode}: KTV ${ktv} đã trên ${hours} giờ kể từ mốc giao việc/bắt đầu mà chưa bấm «Đã xác định nguyên nhân» trên app. Vui lòng kiểm tra hỗ trợ.`;
    const payload = JSON.stringify({
      type: 'KTV_DIAGNOSIS_OVERDUE',
      repair_order_id: row.id,
      bien_so: bien,
      ro_code: roCode,
      ktv_username: ktv,
      sla_hours: hours,
    });

    for (const userId of quanDocIds) {
      await pool.query(`INSERT INTO notifications (user_id, title, body, data) VALUES ($1, $2, $3, $4::jsonb)`, [
        userId,
        title,
        body,
        payload,
      ]);
      notified += 1;
    }
  }

  if (roRes.rows.length > 0) {
    console.log(`[ktv-diagnosis] RO quá hạn nguyên nhân: ${roRes.rows.length} phiếu → ${notified} thông báo user.`);
  }

  return { checked: roRes.rows.length, notified };
}

export function registerKtvDiagnosisEscalationCron(pool) {
  const schedule = process.env.KTV_DIAGNOSIS_CRON || '*/10 * * * *';
  cron.schedule(schedule, async () => {
    try {
      await runKtvDiagnosisEscalationOnce(pool);
    } catch (e) {
      console.error('[CRON] ktv-diagnosis-escalation:', e?.message || e);
    }
  });
}
