/**
 * Điền mẫu Lệnh sửa chữa VF — layout khác Báo giá (cột 5, jobs sau dòng Gò, không có Tổng tiền CV).
 */
import {
  buildVinFastContext,
  mapJobsFromRow,
  mapPartsFromRow,
  setCompanyHeader,
} from './vf_excel_fill.js';

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

function findRow(ws, predicate, maxRow = 220) {
  for (let r = 1; r <= Math.min(ws.rowCount || maxRow, maxRow); r++) {
    if (predicate(ws.getRow(r), r)) return r;
  }
  return null;
}

/** Dòng «PHỤ TÙNG» — chỉ khớp ô cột 2 để tránh nhầm với nội dung công việc. */
function findPartsSectionRow(ws, afterRow = 1) {
  for (let r = afterRow; r <= 220; r++) {
    const t2 = normLabel(cellText(ws.getRow(r).getCell(2).value));
    if (t2 === 'phu tung') return r;
  }
  return null;
}

function rowContains(ws, rowNum, needle) {
  const n = normLabel(needle);
  const row = ws.getRow(rowNum);
  for (let c = 1; c <= 24; c++) {
    if (normLabel(cellText(row.getCell(c).value)).includes(n)) return true;
  }
  return false;
}

const LSC_VALUE_COL = 5;

function fillLscCustomerBlock(ws, ctx) {
  const rSo = findRow(ws, (row) => normLabel(cellText(row.getCell(2).value)).includes('so phieu'));
  if (rSo) setCell(ws, rSo, 2, `Số phiếu: ${ctx.SO_PHIEU}     CVDV: ${ctx.CVDV}`);

  const fields = [
    ['chu xe', ctx.TEN_KH],
    ['dia chi', ctx.DIA_CHI_KH],
    ['dien thoai', ctx.SDT_KH_EMAIL],
    ['nguoi mang xe den', ctx.NGUOI_MANG_XE],
    ['don vi bao hiem', ctx.DON_VI_BH],
    ['thoi gian khach hang toi', ctx.THOI_GIAN_DEN],
    ['thoi gian du kien bat dau', ctx.THOI_GIAN_BAT_DAU],
    ['muc dich su dung', ctx.MUC_DICH],
  ];
  for (const [label, val] of fields) {
    const n = normLabel(label);
    const r = findRow(ws, (row) => {
      for (let c = 1; c <= 6; c++) {
        const t = normLabel(cellText(row.getCell(c).value));
        if (t === n || t.startsWith(`${n}:`) || t.includes(n)) return true;
      }
      return false;
    });
    if (r) setCell(ws, r, LSC_VALUE_COL, val);
  }

  fillRightLsc(ws, 'bien so', ctx.BIEN_SO);
  fillRightLsc(ws, 'ma kieu xe', ctx.MA_KIEU_XE);
  fillRightLsc(ws, 'so khung', ctx.SO_KHUNG);
  fillRightLsc(ws, 'so km', ctx.SO_KM);

  const rYc = findRow(ws, (row) => normLabel(cellText(row.getCell(2).value)).includes('yeu cau khach hang'));
  if (rYc) setCell(ws, rYc, LSC_VALUE_COL, ctx.YEU_CAU_KH);
}

const LSC_RIGHT_VALUE_COL = 31;

function fillRightLsc(ws, labelIncludes, value) {
  const n = normLabel(labelIncludes);
  const r = findRow(ws, (row) => {
    for (let c = 14; c <= 25; c++) {
      const t = normLabel(cellText(row.getCell(c).value));
      if (t === n || t.includes(n)) return true;
    }
    return false;
  });
  if (!r) return;
  masterCell(ws, r, LSC_RIGHT_VALUE_COL).value = null;
  setCell(ws, r, LSC_RIGHT_VALUE_COL, value);
}

function findLscJobsBounds(ws) {
  const secRow = findRow(ws, (row) => {
    for (let c = 1; c <= 20; c++) {
      if (normLabel(cellText(row.getCell(c).value)).includes('noi dung cong viec')) return true;
    }
    return false;
  });
  if (!secRow) return null;

  let lastHeader = null;
  for (let r = secRow + 1; r <= secRow + 12; r++) {
    const row = ws.getRow(r);
    const c2 = normLabel(cellText(row.getCell(2).value));
    const c4 = normLabel(cellText(row.getCell(4).value));
    if (c2 === 'stt' && c4.includes('ma cong')) lastHeader = r;
  }
  if (!lastHeader) return null;

  let dataStart = lastHeader + 1;
  const goRow = findRow(
    ws,
    (_, r) => r > lastHeader && r <= lastHeader + 8 && (rowContains(ws, r, 'go') || rowContains(ws, r, 'gò')),
  );
  if (goRow) {
    dataStart = goRow + 1;
  } else {
    for (let r = lastHeader + 1; r <= lastHeader + 10; r++) {
      if (rowContains(ws, r, 'go') || rowContains(ws, r, 'gò')) {
        dataStart = r + 1;
        break;
      }
      const c2 = normLabel(cellText(ws.getRow(r).getCell(2).value));
      const c4 = normLabel(cellText(ws.getRow(r).getCell(4).value));
      if (c2 === 'stt' && c4.includes('ma cong')) {
        dataStart = r + 1;
        continue;
      }
      const c18 = normLabel(cellText(ws.getRow(r).getCell(18).value));
      if (c18 === 'bat dau' || c18 === 'ket thuc') {
        dataStart = r + 1;
        continue;
      }
      let empty = true;
      for (let c = 2; c <= 11; c++) {
        if (cellText(ws.getRow(r).getCell(c).value)) {
          empty = false;
          break;
        }
      }
      if (empty) {
        dataStart = r + 1;
        continue;
      }
      dataStart = r;
      break;
    }
  }

  const partsRow = findPartsSectionRow(ws, dataStart);
  const dataEnd = partsRow != null ? partsRow : dataStart + 8;

  return { dataStart, dataEnd, templateRow: dataStart };
}

function applyListRows(ws, bounds, items, fillRow, clearCols) {
  if (!bounds) return;
  const { dataStart, dataEnd, templateRow } = bounds;
  const existing = Math.max(0, dataEnd - dataStart);
  const need = items.length;

  if (need > existing) {
    for (let i = 0; i < need - existing; i++) {
      ws.duplicateRow(dataEnd - 1, 1, true);
    }
  }

  for (let i = 0; i < need; i++) {
    const rowNum = dataStart + i;
    fillRow(ws, rowNum, items[i], i + 1, templateRow);
    ws.getRow(rowNum).hidden = false;
  }

  for (let i = need; i < existing; i++) {
    const rowNum = dataStart + i;
    for (let c = 2; c <= 25; c++) masterCell(ws, rowNum, c).value = null;
    ws.getRow(rowNum).hidden = true;
  }
}

function fillLscJobs(ws, jobs, ctx) {
  const bounds = findLscJobsBounds(ws);
  applyListRows(ws, bounds, jobs, (ws, rowNum, item, stt) => {
    setCell(ws, rowNum, 2, stt);
    setCell(ws, rowNum, 4, item.code || '');
    setCell(ws, rowNum, 6, item.name || '');
    setCell(ws, rowNum, 11, ctx.KTV || '');
  }, [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 18, 19]);
}

function findLscPartsBounds(ws) {
  const secRow = findPartsSectionRow(ws, 30);
  if (!secRow) return null;

  let lastHeader = null;
  for (let r = secRow + 1; r <= secRow + 8; r++) {
    const c3 = normLabel(cellText(ws.getRow(r).getCell(3).value));
    const c4 = normLabel(cellText(ws.getRow(r).getCell(4).value));
    if (c3.includes('ma phu') || c4.includes('ma phu')) lastHeader = r;
  }
  if (!lastHeader) return null;

  let dataStart = lastHeader + 1;
  const c2 = normLabel(cellText(ws.getRow(dataStart).getCell(2).value));
  if (c2 === 'stt') dataStart++;

  let dataEnd = dataStart;
  for (let r = dataStart; r < dataStart + 80; r++) {
    const row = ws.getRow(r);
    let empty = true;
    for (let c = 2; c <= 12; c++) {
      if (cellText(row.getCell(c).value)) {
        empty = false;
        break;
      }
    }
    if (empty && r > dataStart) {
      dataEnd = r;
      break;
    }
    dataEnd = r + 1;
  }

  return { dataStart, dataEnd, templateRow: dataStart };
}

function fillLscParts(ws, parts) {
  const bounds = findLscPartsBounds(ws);
  applyListRows(ws, bounds, parts, (ws, rowNum, item, stt) => {
    setCell(ws, rowNum, 2, stt);
    setCell(ws, rowNum, 3, item.code || '');
    setCell(ws, rowNum, 7, item.name || '');
    setCell(ws, rowNum, 13, item.unit || 'Cái');
    setCell(ws, rowNum, 18, item.qty ?? 1);
  }, [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]);
}

export function fillLenhSuaChuaVinFast(ws, row, workshopDefaults = {}) {
  const ctx = buildVinFastContext(row, workshopDefaults);
  setCompanyHeader(ws, ctx.TEN_CONG_TY);
  fillLscCustomerBlock(ws, ctx);
  fillLscJobs(ws, mapJobsFromRow(row), ctx);
  fillLscParts(ws, mapPartsFromRow(row));
}
