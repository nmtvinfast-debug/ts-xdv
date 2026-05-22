/**

 * Điền mẫu VF — Phiếu yêu cầu phụ tùng (layout từ VF - Phiếu yêu cầu phụ tùng.xlsx).

 */

import { buildVinFastContext } from './vf_excel_fill.js';



function cellText(val) {

  if (val == null) return '';

  if (typeof val === 'string') return String(val).trim();

  if (typeof val === 'number' || typeof val === 'boolean') return String(val).trim();

  if (typeof val === 'object') {

    if (val.richText) return val.richText.map((t) => t.text).join('').trim();

    if (val.text) return String(val.text).trim();

  }

  return String(val).trim();

}



function normLabel(s) {

  return String(s || '')

    .toLowerCase()

    .normalize('NFD')

    .replace(/[\u0300-\u036f]/g, '')

    .replace(/\s+/g, ' ')

    .trim();

}



function isGuidLike(s) {

  const t = String(s || '').trim();

  return /^[{(]?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i.test(t);

}



function masterCell(ws, rowNum, col) {

  const cell = ws.getRow(rowNum).getCell(col);

  if (cell.isMerged && cell.master) return cell.master;

  return cell;

}



function setCellSmart(cell, value) {

  const text = value == null ? '' : String(value);

  const v = cell.value;

  if (v && typeof v === 'object' && Array.isArray(v.richText)) {

    const full = v.richText.map((t) => t.text).join('');

    const colon = full.indexOf(':');

    if (colon >= 0) {

      const labelPart = full.slice(0, colon + 1);

      const valueFont = v.richText[v.richText.length - 1]?.font || v.richText[0]?.font || {};

      const labelFont = v.richText[0]?.font || valueFont;

      cell.value = {

        richText: [

          { font: labelFont, text: labelPart },

          { font: valueFont, text: text.startsWith(' ') ? text : ` ${text}` },

        ],

      };

      return;

    }

  }

  cell.value = text;

}



function setCell(ws, rowNum, col, value) {

  setCellSmart(masterCell(ws, rowNum, col), value);

}



function findRow(ws, predicate, maxRow = 80) {

  for (let r = 1; r <= Math.min(ws.rowCount || maxRow, maxRow); r++) {

    if (predicate(ws.getRow(r), r)) return r;

  }

  return null;

}



function findPtTableBounds(ws) {

  const headerRow = findRow(ws, (row) => {

    const c2 = normLabel(cellText(row.getCell(2).value));

    const c4 = normLabel(cellText(row.getCell(4).value));

    return c2 === 'stt' && c4.includes('ma phu');

  });

  if (!headerRow) return null;



  const dataStart = headerRow + 1;

  let dataEnd = dataStart;



  for (let r = dataStart; r < dataStart + 80; r++) {

    const t2 = normLabel(cellText(ws.getRow(r).getCell(2).value));

    if (

      t2.includes('co van') ||

      t2.includes('nguoi phe duyet') ||

      t2 === 'stt'

    ) {

      dataEnd = r;

      break;

    }

    const c4 = cellText(ws.getRow(r).getCell(4).value);

    if (!c4 && r > dataStart) {

      dataEnd = r;

      break;

    }

    dataEnd = r + 1;

  }



  return { dataStart, dataEnd, templateRow: dataStart };

}



function applyListRows(ws, bounds, items, fillRow) {

  if (!bounds) return;

  const { dataStart, dataEnd, templateRow } = bounds;

  const existing = Math.max(0, dataEnd - dataStart);

  const need = items.length;



  if (need > existing) {
    for (let i = 0; i < need - existing; i++) {
      ws.duplicateRow(dataEnd - 1, 1, true);
      dataEnd += 1;
    }
  }



  for (let i = 0; i < need; i++) {

    const rowNum = dataStart + i;

    fillRow(ws, rowNum, items[i], i + 1, templateRow);

    ws.getRow(rowNum).hidden = false;

  }



  for (let i = need; i < existing; i++) {

    const rowNum = dataStart + i;

    for (let c = 2; c <= 16; c++) masterCell(ws, rowNum, c).value = null;

    ws.getRow(rowNum).hidden = true;

  }

}



function mapPartsForPt(row) {

  let parts = row.parts;

  if (typeof parts === 'string') {

    try {

      parts = JSON.parse(parts);

    } catch {

      parts = [];

    }

  }

  if (!Array.isArray(parts)) return [];

  return parts.map((p, i) => {

    const qty = Number(p.qty ?? p.sl ?? 1) || 1;

    let code = String(p.code ?? p.ma ?? '').trim();

    if (isGuidLike(code)) code = '';

    return {

      stt: i + 1,

      code,

      name: String(p.name ?? p.ten ?? '').trim(),

      qty,

      unit: String(p.unit ?? p.dvt ?? 'EA').trim() || 'EA',

      note: String(p.note ?? p.ghi_chu ?? '').trim(),

    };

  });

}



function fillHeader(ws, ctx, row) {

  const rSo = findRow(ws, (r) => {

    const t = normLabel(cellText(r.getCell(2).value));

    return t.startsWith('so:') || t === 'so';

  });

  if (rSo) {

    const so = ctx.SO_PHIEU || row.ro_code || '';

    setCell(ws, rSo, 2, so);

    setCell(ws, rSo, 11, ctx.NGAY_TAO);

  }



  const rCvdv = findRow(ws, (r) => normLabel(cellText(r.getCell(2).value)).includes('co van dich vu'));

  if (rCvdv) {

    const cvdv = ctx.CVDV || row.cvdv_username || '';

    const bs = ctx.BIEN_SO || row.bien_so || '';

    const sk = ctx.SO_KHUNG || '';

    const extra = [bs && `BS: ${bs}`, sk && `SK: ${sk}`].filter(Boolean).join(' · ');

    setCell(ws, rCvdv, 5, extra ? `${cvdv} — ${extra}` : cvdv);

  }



  const rNote = findRow(ws, (r) => normLabel(cellText(r.getCell(2).value)).includes('noi dung de nghi'));

  if (rNote) {

    const note =

      String(row.urgent_note || row.parts_request_note || '').trim() ||

      'Xuất kho theo lệnh sửa chữa';

    setCell(ws, rNote, 5, note);

  }

}



function fillPartsTable(ws, parts) {

  const bounds = findPtTableBounds(ws);

  applyListRows(ws, bounds, parts, (ws, rowNum, item, stt, templateRow) => {

    setCell(ws, rowNum, 2, stt);

    setCell(ws, rowNum, 4, item.code || '');

    setCell(ws, rowNum, 6, item.name || '');

    const qty = Number(item.qty ?? 1) || 1;

    const cellQty = masterCell(ws, rowNum, 12);

    cellQty.value = qty;

    const tplQty = templateRow ? masterCell(ws, templateRow, 12) : null;

    if (tplQty?.numFmt) cellQty.numFmt = tplQty.numFmt;

    else if (!cellQty.numFmt) cellQty.numFmt = '#,##0.00';

    setCell(ws, rowNum, 13, item.unit || 'EA');

    setCell(ws, rowNum, 14, item.note || '');

  });

}



/** Sheet mẫu VF đôi khi đặt tên tab = GUID — đổi tên để Excel không hiển thị GUID làm mã PT. */

export function normalizePtWorksheet(ws) {

  if (!ws) return;

  const name = String(ws.name || '');

  if (/^\{?[0-9a-f]{8}-[0-9a-f]{4}-/i.test(name)) {

    ws.name = 'PhieuYeuCauPT';

  }

}



export function fillPhieuYeuCauPtVinFast(ws, row, workshopDefaults = {}) {

  normalizePtWorksheet(ws);

  const ctx = buildVinFastContext(row, workshopDefaults);

  fillHeader(ws, ctx, row);

  const parts = mapPartsForPt(row);

  fillPartsTable(ws, parts);

}


