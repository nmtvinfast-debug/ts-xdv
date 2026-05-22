/**
 * Nhắc bảo dưỡng theo dòng xe — chuẩn hóa tên (bỏ dấu, khoảng trắng, lowercase).
 */

export function normalizeVehicleModel(raw) {
  return String(raw || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/\s+/g, '')
    .toLowerCase();
}

/** fadil, vf3 → 6 tháng; các dòng còn lại trong danh sách → 12 tháng */
const INTERVAL_6M = ['fadil', 'vf3'];
const INTERVAL_12M = [
  'luxa',
  'luxsa',
  'vfe34',
  'vf5',
  'vf6',
  'vf7',
  'vf8',
  'vf9',
  'limogreen',
  'mvp7',
];

export function maintenanceIntervalMonths(modelRaw) {
  const n = normalizeVehicleModel(modelRaw);
  if (!n) return null;
  if (INTERVAL_6M.some((k) => n.includes(k))) return 6;
  if (INTERVAL_12M.some((k) => n.includes(k))) return 12;
  return null;
}

const DONE_STATUSES = new Set([
  'DA_RA_CONG',
  'DA_RA_CONG_THIEU_PT',
  'XE_RA_XUONG',
  'DA_THANH_TOAN',
  'CHO_QUYET_TOAN',
]);

function parseJsonArray(val) {
  if (Array.isArray(val)) return val;
  if (typeof val === 'string') {
    try {
      const p = JSON.parse(val);
      return Array.isArray(p) ? p : [];
    } catch {
      return [];
    }
  }
  return [];
}

/** RO có công việc / ghi chú liên quan bảo dưỡng định kỳ. */
export function isMaintenanceVisit(ro) {
  const note = normalizeVehicleModel(ro.urgent_note || ro.note || '');
  if (note.includes('baoduong') || note.includes('maintenance')) return true;

  for (const j of parseJsonArray(ro.jobs)) {
    const n = normalizeVehicleModel(j.name ?? j.ten ?? j.code ?? '');
    if (
      n.includes('baoduong') ||
      n.includes('baoduongdinhky') ||
      n.includes('dkbd') ||
      n.includes('maintenance') ||
      n.includes('service')
    ) {
      return true;
    }
  }
  return false;
}

/**
 * @param {Array<object>} repairOrders rows from DB
 * @param {{ includeAllStatuses?: boolean, requireMaintenanceVisit?: boolean }} opts
 */
export function buildMaintenanceReminders(repairOrders, opts = {}) {
  const byPlate = new Map();
  const requireMaint = opts.requireMaintenanceVisit === true;

  for (const ro of repairOrders || []) {
    const plate = String(ro.bien_so || '').trim().toUpperCase();
    if (!plate) continue;
    const model = ro.vehicle_activity || ro.car_model || '';
    const months = maintenanceIntervalMonths(model);
    if (!months) continue;
    if (requireMaint && !isMaintenanceVisit(ro)) continue;

    const status = String(ro.status || '').toUpperCase();
    const serviceAt = ro.time_out || ro.time_done || ro.time_in || ro.created_at;
    if (!serviceAt) continue;
    if (!DONE_STATUSES.has(status) && !opts.includeAllStatuses) continue;

    const dt = new Date(serviceAt);
    if (Number.isNaN(dt.getTime())) continue;

    const prev = byPlate.get(plate);
    if (!prev || dt > prev.lastServiceAt) {
      byPlate.set(plate, {
        bien_so: plate,
        vehicle_model: model,
        vehicle_model_norm: normalizeVehicleModel(model),
        interval_months: months,
        last_service_at: dt.toISOString(),
        lastServiceAt: dt,
        customer_name: ro.customer_name || '',
        customer_phone: ro.customer_phone || '',
        last_ro_code: ro.ro_code || '',
        linked_customer: ro.linked_customer || '',
      });
    }
  }

  const now = new Date();
  const out = [];
  for (const item of byPlate.values()) {
    const next = new Date(item.lastServiceAt);
    next.setMonth(next.getMonth() + item.interval_months);
    const overdue = next <= now;
    const daysUntil = Math.ceil((next - now) / (86400000));
    out.push({
      ...item,
      next_reminder_at: next.toISOString(),
      next_reminder_display: next.toLocaleDateString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh' }),
      overdue,
      days_until: daysUntil,
      status_label: overdue ? 'Đến hạn bảo dưỡng' : (daysUntil <= 30 ? 'Sắp đến hạn' : 'Theo dõi'),
    });
  }

  out.sort((a, b) => {
    if (a.overdue !== b.overdue) return a.overdue ? -1 : 1;
    return a.days_until - b.days_until;
  });

  return out;
}
