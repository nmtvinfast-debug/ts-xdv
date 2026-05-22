/**
 * Theo dõi hóa đơn đầu vào PT — file tồn kho kế toán (Mã hàng, Tên hàng, ĐVT, Cuối kỳ, Đơn giá cố định).
 */

export function normalizePartCode(code) {
  return String(code || '')
    .trim()
    .toUpperCase()
    .replace(/\s+/g, '');
}

function normHeader(cell) {
  return String(cell || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

function numVal(v) {
  if (v == null || v === '') return 0;
  if (typeof v === 'number') return v;
  const s = String(v).replace(/,/g, '.').replace(/\s/g, '');
  const n = Number(s);
  return Number.isFinite(n) ? n : 0;
}

/** Làm tròn số nguyên — không lấy phần thập phân. */
export function roundInt(n) {
  if (n == null || n === '') return null;
  const v = Number(n);
  if (!Number.isFinite(v)) return null;
  return Math.round(v);
}

/**
 * File «Tổng hợp tồn kho» — hàng có: Mã hàng, Tên hàng, ĐVT, Cuối kỳ (SL), Đơn giá cố định.
 * Upload mới thay hoàn toàn bản cũ.
 */
export function parseInvoiceUploadRows(rows) {
  let headerIdx = -1;
  let colCode = 1;
  let colName = 2;
  let colUnit = 3;
  let colQty = 4;
  let colValue = 5;
  let colFixed = 6;

  for (let i = 0; i < Math.min(rows.length, 30); i++) {
    const row = rows[i];
    if (!Array.isArray(row)) continue;
    const cells = row.map((c) => normHeader(c));
    const codeIdx = cells.findIndex((c) => c.includes('ma hang') || c.includes('ma phu'));
    if (codeIdx < 0) continue;
    headerIdx = i;
    colCode = codeIdx;
    colName = cells.findIndex((c) => c.includes('ten hang') || c.includes('ten phu'));
    if (colName < 0) colName = colCode + 1;
    colUnit = cells.findIndex((c) => c === 'dvt' || c.includes('don vi'));
    if (colUnit < 0) colUnit = colName + 1;
    colQty = cells.findIndex((c) => c.includes('cuoi ky') || c.includes('so luong'));
    if (colQty < 0) colQty = colUnit + 1;
    const subRow = rows[i + 1];
    if (Array.isArray(subRow)) {
      const sub = subRow.map((c) => normHeader(c));
      const vIdx = sub.findIndex((c) => c.includes('gia tri'));
      if (vIdx >= 0) colValue = vIdx;
      const qIdx = sub.findIndex((c) => c.includes('so luong'));
      if (qIdx >= 0) colQty = qIdx;
    }
    if (colValue < 0 || colValue === colQty) colValue = colQty + 1;
    colFixed = cells.findIndex((c) => c.includes('don gia co dinh') || c.includes('don gia'));
    if (colFixed < 0) colFixed = colValue + 1;
    break;
  }

  const items = [];
  const start = headerIdx >= 0 ? headerIdx + 2 : 0;

  for (let i = start; i < rows.length; i++) {
    const row = rows[i];
    if (!Array.isArray(row) || row.length < 2) continue;
    const rawCode = String(row[colCode] ?? '').trim();
    if (!rawCode) continue;
    const joined = row.map((c) => normHeader(c)).join(' ');
    if (joined.includes('ma hang') || joined.includes('tong cong') || rawCode.toLowerCase() === 'stt') continue;

    const code = normalizePartCode(rawCode);
    if (code.length < 2) continue;

    const name = String(row[colName] ?? '').trim();
    const unit = String(row[colUnit] ?? 'Cái').trim() || 'Cái';
    const stock_qty = roundInt(numVal(row[colQty]));
    const stock_value = roundInt(numVal(row[colValue]));
    const fixed_price = roundInt(numVal(row[colFixed]));

    items.push({
      code,
      name,
      unit,
      stock_qty,
      stock_value,
      fixed_price,
      raw_code: rawCode,
    });
  }

  const map = new Map();
  for (const it of items) map.set(it.code, it);
  return [...map.values()];
}

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

/** Tồn kho còn lại sau khi trừ các RO đã «đã xuất HĐ». */
export function buildStockAvailableMap(uploadItems, issuedRoIds, repairOrders) {
  const map = new Map();
  for (const it of uploadItems || []) {
    const code = normalizePartCode(it.code);
    if (!code) continue;
    map.set(code, roundInt(it.stock_qty) ?? 0);
  }
  for (const ro of repairOrders || []) {
    if (!issuedRoIds.has(String(ro.id))) continue;
    for (const p of parseJsonArray(ro.parts)) {
      const code = normalizePartCode(p.code ?? p.ma ?? '');
      if (!code || !map.has(code)) continue;
      const qty = roundInt(Number(p.qty ?? p.sl ?? 1) || 1) ?? 1;
      map.set(code, Math.max(0, (map.get(code) ?? 0) - qty));
    }
  }
  return map;
}

function roPartsStockOk(parts, invMap, stockAvail) {
  for (const p of parts) {
    const code = normalizePartCode(p.code ?? p.ma ?? '');
    if (!code) continue;
    if (!invMap.has(code)) return false;
    const need = roundInt(Number(p.qty ?? p.sl ?? 1) || 1) ?? 1;
    if ((stockAvail.get(code) ?? 0) < need) return false;
  }
  return true;
}

/** Trừ tồn kho file upload khi kế toán xác nhận xuất HĐ. */
export function deductInvoiceStockItems(uploadItems, parts) {
  const byCode = new Map((uploadItems || []).map((it) => [normalizePartCode(it.code), { ...it }]));
  for (const p of parts || []) {
    const code = normalizePartCode(p.code ?? p.ma ?? '');
    if (!code) continue;
    const it = byCode.get(code);
    if (!it || it.stock_qty == null) continue;
    const need = roundInt(Number(p.qty ?? p.sl ?? 1) || 1) ?? 1;
    it.stock_qty = Math.max(0, (roundInt(it.stock_qty) ?? 0) - need);
  }
  return [...byCode.values()];
}

function pickPay(ro, key, alt) {
  const v = ro[key] ?? ro[alt];
  return Number(v) || 0;
}

/** Set mã RO đã kế toán xác nhận «đã xuất hóa đơn». */
export function getIssuedRoIdSet(workshopDefaults = {}) {
  const raw = workshopDefaults.invoice_issued_ro_ids;
  if (!raw || typeof raw !== 'object') return new Set();
  return new Set(Object.keys(raw).map(String));
}

/**
 * @param {object} ro
 * @param {Map<string, object>} invoicedParts — mã PT có trong file tồn kho kế toán
 * @param {Map<string, object>} inventoryByCode — giá nhập kho TS (nếu có)
 * @param {Set<string>} issuedRoIds — RO kế toán đã bấm «đã xuất HĐ»
 */
export function buildVehicleInvoiceStatus(ro, invoicedParts, inventoryByCode, issuedRoIds = new Set()) {
  const jobs = parseJsonArray(ro.jobs);
  const parts = parseJsonArray(ro.parts);
  const lines = [];

  for (const j of jobs) {
    const code = String(j.code ?? j.ma ?? '').trim();
    if (!code) continue;
    const qty = roundInt(Number(j.qty ?? j.hours ?? 1) || 1) ?? 1;
    const priceOut = roundInt(Number(j.price ?? j.don_gia ?? 0) || 0) ?? 0;
    const totalOut = roundInt(Number(j.total ?? j.totalWithVat ?? qty * priceOut) || qty * priceOut) ?? 0;
    lines.push({
      type: 'job',
      code,
      name: String(j.name ?? j.ten ?? '').trim(),
      unit: 'Giờ',
      qty,
      fixed_price: null,
      price_in: null,
      price_out: priceOut,
      price_diff: null,
      total_out: totalOut,
      total_in: null,
      stock_qty: null,
      stock_value: null,
      has_invoice: true,
      invoice_status: 'cong_viec',
    });
  }

  for (const p of parts) {
    const code = normalizePartCode(p.code ?? p.ma ?? '');
    if (!code) continue;
    const inv = invoicedParts.get(code);
    const stock = inventoryByCode.get(code);
    const qty = roundInt(Number(p.qty ?? p.sl ?? 1) || 1) ?? 1;
    const priceOut = roundInt(Number(p.price ?? p.don_gia ?? 0) || 0) ?? 0;
    const totalOut = roundInt(Number(p.total ?? p.totalWithVat ?? qty * priceOut) || qty * priceOut) ?? 0;
    const fixedPrice = inv?.fixed_price != null ? roundInt(inv.fixed_price) : null;
    const priceIn =
      fixedPrice != null
        ? fixedPrice
        : stock?.price_in != null
          ? roundInt(stock.price_in)
          : null;
    const totalIn = priceIn != null ? roundInt(priceIn * qty) : null;
    const priceDiff = priceIn != null ? roundInt(priceOut - priceIn) : null;

    lines.push({
      type: 'part',
      code,
      name: String(inv?.name ?? p.name ?? p.ten ?? '').trim(),
      unit: String(inv?.unit ?? p.unit ?? 'Cái').trim(),
      qty,
      fixed_price: fixedPrice,
      price_in: priceIn,
      price_out: priceOut,
      price_diff: priceDiff,
      total_out: totalOut,
      total_in: totalIn,
      has_invoice: Boolean(inv),
      invoice_status: inv ? 'da_co_hd_dau_vao' : 'chua_co_hd',
      stock_qty: inv?.stock_qty != null ? roundInt(inv.stock_qty) : null,
      stock_value: inv?.stock_value != null ? roundInt(inv.stock_value) : null,
    });
  }

  const partLines = lines.filter((l) => l.type === 'part');
  const needInvoice = partLines.length > 0;
  const allPartsInStockFile = partLines.length === 0 || partLines.every((l) => l.has_invoice);
  const missing = partLines.filter((l) => !l.has_invoice);
  const roId = String(ro.id);
  const accountantIssued = issuedRoIds.has(roId);

  return {
    ro_id: ro.id,
    ro_code: ro.ro_code,
    bien_so: ro.bien_so,
    customer_name: ro.customer_name,
    status: ro.status,
    need_invoice: needInvoice,
    /** Đủ PT trong file tồn kho — có thể xuất HĐ (chưa chuyển tab). */
    parts_ready: needInvoice && allPartsInStockFile,
    ready_to_issue: needInvoice && allPartsInStockFile,
    stock_sufficient: true,
    /** Kế toán đã bấm «Đã xuất hóa đơn». */
    accountant_issued: accountantIssued,
    invoice_tab: accountantIssued ? 'da_xuat_hd' : 'chua_xuat_hd',
    missing_parts_count: missing.length,
    lines,
    missing_parts: missing,
    payment: {
      customer: pickPay(ro, 'customer_pay', 'customerPay'),
      insurance: pickPay(ro, 'insurance_pay', 'insurancePay'),
      warranty: pickPay(ro, 'warranty_pay', 'warrantyPay'),
      internal: pickPay(ro, 'debt', 'cong_no'),
    },
  };
}

export function buildInvoiceTrackingReport(repairOrders, invoicedParts, inventoryItems, issuedRoIds = new Set()) {
  const invMap = new Map();
  for (const it of invoicedParts || []) invMap.set(it.code, it);

  const stockMap = new Map();
  for (const it of inventoryItems || []) {
    const code = normalizePartCode(it.part_code ?? it.code ?? '');
    if (code) stockMap.set(code, it);
  }

  const stockAvail = buildStockAvailableMap(invoicedParts, issuedRoIds, repairOrders);

  const vehicles = [];
  for (const ro of repairOrders || []) {
    const parts = parseJsonArray(ro.parts);
    if (parts.length === 0) continue;
    vehicles.push(buildVehicleInvoiceStatus(ro, invMap, stockMap, issuedRoIds));
  }

  const pendingByTime = vehicles
    .filter((v) => !v.accountant_issued)
    .sort((a, b) => {
      const ta = repairOrders.find((r) => String(r.id) === String(a.ro_id))?.time_in;
      const tb = repairOrders.find((r) => String(r.id) === String(b.ro_id))?.time_in;
      return new Date(ta || 0) - new Date(tb || 0);
    });

  for (const v of pendingByTime) {
    const ro = repairOrders.find((r) => String(r.id) === String(v.ro_id));
    if (!ro) continue;
    const parts = parseJsonArray(ro.parts);
    const ok = roPartsStockOk(parts, invMap, stockAvail);
    if (!ok) {
      v.parts_ready = false;
      v.ready_to_issue = false;
      v.stock_sufficient = false;
    } else {
      for (const p of parts) {
        const code = normalizePartCode(p.code ?? p.ma ?? '');
        const need = roundInt(Number(p.qty ?? p.sl ?? 1) || 1) ?? 1;
        stockAvail.set(code, (stockAvail.get(code) ?? 0) - need);
      }
    }
  }

  vehicles.sort((a, b) => {
    if (a.accountant_issued !== b.accountant_issued) return a.accountant_issued ? 1 : -1;
    if (a.parts_ready !== b.parts_ready) return a.parts_ready ? -1 : 1;
    return (b.missing_parts_count || 0) - (a.missing_parts_count || 0);
  });

  const pending = vehicles.filter((v) => !v.accountant_issued);

  return {
    uploaded_parts_count: invMap.size,
    vehicles,
    ready_count: pending.filter((v) => v.parts_ready).length,
    pending_count: pending.filter((v) => !v.parts_ready).length,
    invoiced_count: vehicles.filter((v) => v.accountant_issued).length,
    not_invoiced_count: pending.length,
  };
}
