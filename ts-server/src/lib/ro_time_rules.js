/**
 * Time Rules + audit theo đặc tả TS-XDV (nguyên tắc màn hình và rule.txt)
 * — mốc time_*, pause/resume, actor trên audit, trường tính toán cho API list/detail.
 */

const PAUSE_STATUSES = new Set(['DUNG_SUA', 'CHO_PHU_TUNG']);
const PAUSE_REASONS = new Set(['CHO_PHU_TUNG', 'CHO_KH', 'CHO_BAO_HIEM', 'KHAC']);

/** Bearer `auth_token_<id>` hoặc `local_token_<username>` (đăng nhập staff_db). */
export function parseBearerTokenId(req) {
  const raw = req.headers?.authorization || '';
  const trimmed = String(raw).trim();
  const m = /^Bearer\s+auth_token_(\S+)$/i.exec(trimmed);
  return m ? m[1] : null;
}

export function parseBearerLocalUsername(req) {
  const raw = req.headers?.authorization || '';
  const trimmed = String(raw).trim();
  const m = /^Bearer\s+local_token_(\S+)$/i.exec(trimmed);
  return m ? m[1] : null;
}

/** Bearer auth_token_<id> hoặc local_token_<username> */
export function parseBearerActor(req) {
  const id = parseBearerTokenId(req);
  if (id) return { user_id: id };
  const username = parseBearerLocalUsername(req);
  if (username) return { username };
  return null;
}

export const REPAIR_ORDER_PATCH_KEYS = new Set([
  'status',
  'cvdv_username',
  'ktv_username',
  'jobs',
  'parts',
  'chat_logs',
  'linked_customer',
  'link_requested_by',
  'customer_note',
  'urgent_note',
  'images',
  'payment_info',
  'customer_waiting',
  'is_insurance',
  'planned_time_mins',
  'cvdv_wo_code',
  'vehicle_activity',
  'fault_diagnosis_at',
]);

export function sanitizeRepairOrderPatchBody(body) {
  const out = {};
  for (const [k, v] of Object.entries(body || {})) {
    if (REPAIR_ORDER_PATCH_KEYS.has(k)) out[k] = v;
  }
  return out;
}

export function repairOrderMilestoneSqlFragments(newStatus) {
  const s = newStatus;
  const frag = [];
  if (s === 'CHO_BAO_GIA') frag.push('time_quote_created = COALESCE(time_quote_created, NOW())');
  if (s === 'CHO_KH_DUYET') frag.push('time_quote_sent = COALESCE(time_quote_sent, NOW())');
  if (s === 'CHO_PHAN_CONG') frag.push('time_quote_approved = COALESCE(time_quote_approved, NOW())');
  if (s === 'CHO_SUA_CHUA') frag.push('time_assign = COALESCE(time_assign, NOW())');
  if (s === 'DANG_SUA') frag.push('time_start = COALESCE(time_start, NOW())');
  if (s === 'CHO_QUYET_TOAN' || s === 'DA_RA_CONG' || s === 'DA_RA_CONG_THIEU_PT' || s === 'HUY_CHO_QUYET_TOAN') {
    frag.push('time_done = COALESCE(time_done, NOW())');
    frag.push('time_ready_for_settlement = COALESCE(time_ready_for_settlement, NOW())');
  }
  if (s === 'DA_THANH_TOAN') frag.push('time_paid = COALESCE(time_paid, NOW())');
  if (s === 'XE_RA_XUONG' || s === 'DA_RA_CONG' || s === 'DA_RA_CONG_THIEU_PT') {
    frag.push('time_out = COALESCE(time_out, NOW())');
  }
  return frag;
}

export function appendRepairOrderAuditHistory(row, fromStatus, toStatus, note, actor, action = 'status_change') {
  let h = row.audit_history;
  if (h == null) h = [];
  if (typeof h === 'string') {
    try {
      h = JSON.parse(h);
    } catch {
      h = [];
    }
  }
  if (!Array.isArray(h)) h = [];
  const entry = {
    at: new Date().toISOString(),
    action,
    from_status: fromStatus,
    to_status: toStatus,
  };
  if (actor?.user_id) entry.user_id = actor.user_id;
  if (note != null && String(note).trim() !== '') entry.note = String(note).trim().slice(0, 2000);
  return [...h, entry];
}

export function normalizePauses(val) {
  let pauses = val;
  if (pauses == null) return [];
  if (typeof pauses === 'string') {
    try {
      pauses = JSON.parse(pauses);
    } catch {
      return [];
    }
  }
  if (!Array.isArray(pauses)) return [];
  return pauses.map((p) => (typeof p === 'object' && p ? { ...p } : p)).filter(Boolean);
}

function pauseCluster(status) {
  return PAUSE_STATUSES.has(status);
}

/**
 * pause_reason: CHO_PHU_TUNG | CHO_KH | CHO_BAO_HIEM | KHAC (theo rule §4)
 */
export function applyPauseResumeOnStatusChange(oldRow, oldStatus, newStatus, pauseReason, actor) {
  if (oldStatus === newStatus) return null;
  const pauses = normalizePauses(oldRow.pauses);
  if (pauseCluster(newStatus)) {
    const reason = PAUSE_REASONS.has(pauseReason) ? pauseReason : 'KHAC';
    pauses.push({
      pause_at: new Date().toISOString(),
      reason,
      user_id: actor?.user_id || null,
    });
    return pauses;
  }
  if (pauseCluster(oldStatus) && !pauseCluster(newStatus)) {
    for (let i = pauses.length - 1; i >= 0; i--) {
      const seg = pauses[i];
      if (seg && seg.pause_at && !seg.resume_at) {
        pauses[i] = {
          ...seg,
          resume_at: new Date().toISOString(),
          resume_user_id: actor?.user_id || null,
        };
        break;
      }
    }
    return pauses;
  }
  return null;
}

/** Phút từ mốc KTV xử lý: time_start, rồi time_assign, rồi last_status_changed — SLA kiểm tra / nguyên nhân lỗi. */
export function ktvInspectionElapsedMinutes(row) {
  const ref = row.time_start || row.time_assign || row.last_status_changed_at || row.time_in;
  if (!ref) return null;
  const t = new Date(ref).getTime();
  if (Number.isNaN(t)) return null;
  return Math.floor((Date.now() - t) / 60000);
}

/** Thời gian tồn trạng thái (phút) — Rule §2 */
export function minutesInCurrentState(row) {
  const ref = row.last_status_changed_at || row.updated_at || row.time_in;
  if (!ref) return null;
  const t = new Date(ref).getTime();
  if (Number.isNaN(t)) return null;
  return Math.floor((Date.now() - t) / 60000);
}

export function openPauseSegment(row) {
  const pauses = normalizePauses(row.pauses);
  for (let i = pauses.length - 1; i >= 0; i--) {
    const p = pauses[i];
    if (p && p.pause_at && !p.resume_at) return p;
  }
  return null;
}

/**
 * Tổng thời gian pause đã đóng (ms) — nền cho actual_repair_time Rule §3
 */
export function sumClosedPauseDurationMs(pausesVal) {
  const pauses = normalizePauses(pausesVal);
  let sum = 0;
  for (const p of pauses) {
    if (!p?.pause_at || !p.resume_at) continue;
    const a = new Date(p.pause_at).getTime();
    const b = new Date(p.resume_at).getTime();
    if (!Number.isNaN(a) && !Number.isNaN(b) && b > a) sum += b - a;
  }
  return sum;
}

/**
 * Danh sách RO: bỏ ảnh base64 / chat dài — tránh JSON quá lớn → Fly/proxy HTTP 502.
 * Chi tiết đầy đủ: GET /repair-orders/:id
 */
export function lightenRepairOrderForList(row) {
  const out = { ...row };

  let imgs = out.images;
  if (imgs == null) imgs = [];
  else if (typeof imgs === 'string') {
    try {
      imgs = JSON.parse(imgs);
    } catch {
      imgs = [];
    }
  }
  if (!Array.isArray(imgs)) imgs = [];

  let omittedEmbedded = 0;
  const lightImages = [];
  for (const img of imgs) {
    if (typeof img === 'string') {
      if (img.startsWith('data:image') || img.length > 512) {
        omittedEmbedded += 1;
        continue;
      }
      lightImages.push(img);
      continue;
    }
    lightImages.push(img);
  }
  out.has_images = imgs.length > 0;
  out.images_embedded_omitted = omittedEmbedded;
  out.images = lightImages;

  let logs = out.chat_logs;
  if (typeof logs === 'string') {
    try {
      logs = JSON.parse(logs);
    } catch {
      logs = [];
    }
  }
  if (Array.isArray(logs) && logs.length > 8) {
    out.chat_logs = logs.slice(-8);
  }

  return out;
}

export function enrichRepairOrderRow(row) {
  const minutes_in_state = minutesInCurrentState(row);
  const ktv_inspection_elapsed_minutes = ktvInspectionElapsedMinutes(row);
  const state_entered_at = row.last_status_changed_at || row.updated_at || row.time_in;
  const open_pause = openPauseSegment(row);
  const pause_ms_closed = sumClosedPauseDurationMs(row.pauses);
  return {
    ...row,
    minutes_in_state,
    ktv_inspection_elapsed_minutes,
    state_entered_at,
    open_pause,
    pause_duration_closed_ms: pause_ms_closed,
  };
}
