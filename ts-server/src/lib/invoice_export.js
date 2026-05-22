import ExcelJS from 'exceljs';
import { buildVehicleInvoiceStatus, normalizePartCode, roundInt } from './invoice_tracking.js';

const INT_FMT = '#,##0';
const MONEY_COLS = new Set([
  'qty',
  'fixed_price',
  'price_in',
  'price_out',
  'price_diff',
  'total_in',
  'total_out',
  'stock_qty',
  'stock_value',
]);

function styleHeaderRow(row) {
  row.font = { bold: true, size: 11 };
  row.alignment = { vertical: 'middle', horizontal: 'center', wrapText: true };
  row.height = 22;
  row.eachCell((cell) => {
    cell.fill = {
      type: 'pattern',
      pattern: 'solid',
      fgColor: { argb: 'FFE8EEF7' },
    };
    cell.border = {
      top: { style: 'thin' },
      left: { style: 'thin' },
      bottom: { style: 'thin' },
      right: { style: 'thin' },
    };
  });
}

function applyRowStyle(row) {
  row.eachCell({ includeEmpty: false }, (cell, colNumber) => {
    const key = row.worksheet.getColumn(colNumber).key;
    if (key && MONEY_COLS.has(key) && typeof cell.value === 'number') {
      cell.numFmt = INT_FMT;
    }
    cell.border = {
      top: { style: 'thin', color: { argb: 'FFD0D0D0' } },
      left: { style: 'thin', color: { argb: 'FFD0D0D0' } },
      bottom: { style: 'thin', color: { argb: 'FFD0D0D0' } },
      right: { style: 'thin', color: { argb: 'FFD0D0D0' } },
    };
  });
}

function numOrBlank(v) {
  const r = roundInt(v);
  return r == null ? '' : r;
}

/**
 * Xuất Excel chi tiết theo dõi HĐ cho một xe (RO).
 */
export async function buildInvoiceVehicleWorkbook(ro, invoicedParts, inventoryItems) {
  const invMap = new Map((invoicedParts || []).map((it) => [normalizePartCode(it.code), it]));
  const stockMap = new Map();
  for (const it of inventoryItems || []) {
    const c = normalizePartCode(it.part_code ?? it.code ?? '');
    if (c) stockMap.set(c, it);
  }

  const st = buildVehicleInvoiceStatus(ro, invMap, stockMap);
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet('Theo doi HD', {
    views: [{ state: 'frozen', ySplit: 1 }],
  });

  ws.columns = [
    { header: 'Loại', key: 'type', width: 11 },
    { header: 'Mã công việc / Mã PT', key: 'code', width: 22 },
    { header: 'Tên hàng', key: 'name', width: 42 },
    { header: 'ĐVT', key: 'unit', width: 10 },
    { header: 'SL trên phiếu', key: 'qty', width: 14 },
    { header: 'Đơn giá cố định', key: 'fixed_price', width: 16 },
    { header: 'Giá nhập', key: 'price_in', width: 14 },
    { header: 'Giá xuất (CVDV)', key: 'price_out', width: 16 },
    { header: 'Chênh lệch', key: 'price_diff', width: 14 },
    { header: 'Thành tiền nhập', key: 'total_in', width: 16 },
    { header: 'Thành tiền xuất', key: 'total_out', width: 16 },
    { header: 'Cuối kỳ — Số lượng', key: 'stock_qty', width: 16 },
    { header: 'Cuối kỳ — Giá trị', key: 'stock_value', width: 16 },
    { header: 'HĐ đầu vào', key: 'invoice_status', width: 20 },
  ];

  styleHeaderRow(ws.getRow(1));

  const infoRow = ws.addRow({
    type: 'THÔNG TIN',
    code: st.ro_code,
    name: `${st.bien_so} — ${st.customer_name}`,
    invoice_status: st.parts_ready ? 'Đủ PT — có thể xuất HĐ' : 'Chưa đủ PT trong file tồn kho',
  });
  infoRow.font = { bold: true };
  ws.addRow({});

  for (const l of st.lines) {
    const dataRow = ws.addRow({
      type: l.type === 'job' ? 'Công việc' : 'Phụ tùng',
      code: l.code,
      name: l.name,
      unit: l.unit,
      qty: numOrBlank(l.qty),
      fixed_price: numOrBlank(l.fixed_price),
      price_in: numOrBlank(l.price_in),
      price_out: numOrBlank(l.price_out),
      price_diff: numOrBlank(l.price_diff),
      total_in: numOrBlank(l.total_in),
      total_out: numOrBlank(l.total_out),
      stock_qty: l.type === 'part' ? numOrBlank(l.stock_qty) : '',
      stock_value: l.type === 'part' ? numOrBlank(l.stock_value) : '',
      invoice_status:
        l.type === 'job'
          ? 'Theo quyết toán CVDV'
          : l.has_invoice
            ? 'Đã có HĐ đầu vào'
            : 'Chưa có HĐ đầu vào',
    });
    applyRowStyle(dataRow);
  }

  ws.addRow({});
  const sumRow = ws.addRow({
    type: 'Tổng hợp',
    name: st.accountant_issued
      ? 'Đã xuất hóa đơn (kế toán xác nhận)'
      : st.parts_ready
        ? 'Đủ PT — chờ kế toán xuất HĐ'
        : `Thiếu ${st.missing_parts_count} mã PT`,
  });
  sumRow.font = { bold: true };

  return wb;
}
