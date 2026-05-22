/**

 * Điền dữ liệu RO vào mẫu Excel VinFast — giữ merge & định dạng gốc.

 */

import { fillLenhSuaChuaVinFast } from './vf_excel_lsc.js';



function cellText(val) {

  if (val == null) return '';

  if (typeof val === 'string' || typeof val === 'number' || typeof val === 'boolean') {

    return String(val).trim();

  }

  if (typeof val === 'object') {

    if (val.richText) return val.richText.map((t) => t.text).join('').trim();

    if (val.text) return String(val.text).trim();

    if (val.formula) return '';

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



function fmtVnDateTime(d) {

  if (!d) return '';

  const dt = d instanceof Date ? d : new Date(d);

  if (Number.isNaN(dt.getTime())) return '';

  return dt.toLocaleString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh', hour12: true });

}



function fmtVnDateSlash(d) {

  if (!d) return '';

  const dt = d instanceof Date ? d : new Date(d);

  if (Number.isNaN(dt.getTime())) return '';

  const p = new Intl.DateTimeFormat('vi-VN', {

    timeZone: 'Asia/Ho_Chi_Minh',

    year: 'numeric',

    month: '2-digit',

    day: '2-digit',

  }).formatToParts(dt);

  const y = p.find((x) => x.type === 'year')?.value;

  const m = p.find((x) => x.type === 'month')?.value;

  const day = p.find((x) => x.type === 'day')?.value;

  return `${y}/${m}/${day}`;

}



function fmtMoney(n) {

  const v = Math.round(Number(n) || 0);

  return v.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');

}



/** Ô gốc nếu nằm trong vùng merge (tránh ghi trùng làm vỡ layout). */

function masterCell(ws, rowNum, col) {

  const cell = ws.getRow(rowNum).getCell(col);

  if (cell.isMerged && cell.master) return cell.master;

  return cell;

}



/** Giữ richText sau dấu ":" nếu mẫu có sẵn. */

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



function setMoneyCell(ws, rowNum, col, amount, templateRow) {

  const cell = masterCell(ws, rowNum, col);

  const n = Math.round(Number(amount) || 0);

  cell.value = n;

  const tpl = templateRow ? masterCell(ws, templateRow, col) : null;

  if (tpl?.numFmt) cell.numFmt = tpl.numFmt;

  else if (!cell.numFmt) cell.numFmt = '#,##0';

}

function excelColLetter(col) {
  let n = col;
  let s = '';
  while (n > 0) {
    const m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = Math.floor((n - 1) / 26);
  }
  return s;
}

/** Vùng gộp ô số tiền thanh toán — Báo giá F:K, Quyết toán H:K (giữ cột con hẹp như mẫu). */
function payValueMergeCols(templateKey) {
  return templateKey === 'quyet_toan' ? { start: 8, end: 11 } : { start: 6, end: 11 };
}

function snapshotColumnWidths(ws, fromCol, toCol) {
  const widths = {};
  for (let c = fromCol; c <= toCol; c++) {
    const w = ws.getColumn(c).width;
    if (w != null) widths[c] = w;
  }
  return widths;
}

function restoreColumnWidths(ws, widths) {
  for (const [c, w] of Object.entries(widths)) {
    if (w != null) ws.getColumn(Number(c)).width = w;
  }
}

function tryUnmerge(ws, range) {
  try {
    ws.unMergeCells(range);
  } catch {
    /* ignore */
  }
}

function safeMergeCells(ws, range) {
  try {
    ws.mergeCells(range);
  } catch (err) {
    const msg = String(err?.message || err);
    if (/already merged|Cannot merge/i.test(msg)) return;
    throw err;
  }
}

function preparePayFooterRowMerge(ws, rowNum, templateKey, widthSnapshot) {
  const { start, end } = payValueMergeCols(templateKey);
  const row = String(rowNum);
  tryUnmerge(ws, `${excelColLetter(start)}${row}:${excelColLetter(start + 1)}${row}`);
  if (templateKey === 'bao_gia') tryUnmerge(ws, `I${row}:S${row}`);
  if (templateKey === 'quyet_toan') {
    tryUnmerge(ws, `H${row}:J${row}`);
    tryUnmerge(ws, `K${row}:L${row}`);
  }
  const range = `${excelColLetter(start)}${row}:${excelColLetter(end)}${row}`;
  tryUnmerge(ws, range);
  safeMergeCells(ws, range);
  restoreColumnWidths(ws, widthSnapshot);
  const cell = masterCell(ws, rowNum, start);
  const prev = cell.alignment && typeof cell.alignment === 'object' ? cell.alignment : {};
  cell.alignment = { ...prev, horizontal: 'right', vertical: 'middle', wrapText: false };
  return cell;
}

function setPayFooterCell(ws, rowNum, _payCol, amount, templateKey, widthSnapshot) {
  const cell = preparePayFooterRowMerge(ws, rowNum, templateKey, widthSnapshot);
  const n = Math.round(Number(amount) || 0);
  cell.value = n;
  cell.numFmt = '#,##0';
}



function findRow(ws, predicate, maxRow = 220) {

  for (let r = 1; r <= Math.min(ws.rowCount || maxRow, maxRow); r++) {

    if (predicate(ws.getRow(r), r)) return r;

  }

  return null;

}



function rowContains(ws, rowNum, needle) {

  const n = normLabel(needle);

  const row = ws.getRow(rowNum);

  for (let c = 1; c <= 24; c++) {

    const t = normLabel(cellText(row.getCell(c).value));

    if (t.includes(n)) return true;

  }

  return false;

}



function rowLabelIncludes(row, needle, { minCol = 1, maxCol = 8 } = {}) {

  const n = normLabel(needle);

  for (let c = minCol; c <= maxCol; c++) {

    const t = normLabel(cellText(row.getCell(c).value));

    if (t.includes(n)) return true;

  }

  return false;

}



function fillLabelBlock(ws, labelIncludes, value, { valueCol = 7, dynamicValueCol = false } = {}) {

  const n = normLabel(labelIncludes);

  const r = findRow(ws, (row) => {

    for (let c = 1; c <= 8; c++) {

      const t = normLabel(cellText(row.getCell(c).value));

      if (t === n || t.startsWith(`${n}:`) || t.includes(n)) return true;

    }

    return false;

  });

  if (!r) return false;

  const col = dynamicValueCol ? findVinFastRightValueCol(ws, r, valueCol) : valueCol;

  if (dynamicValueCol) clearVinFastRightSampleValues(ws, r);

  setCell(ws, r, col, value);

  return true;

}



/** Cột giá trị khối phải mẫu Báo giá / Quyết toán (richText «: …»). */
const VF_RIGHT_VALUE_COL = 27;

function findVinFastRightValueCol(ws, rowNum, fallback = VF_RIGHT_VALUE_COL) {
  const row = ws.getRow(rowNum);
  for (let c = 17; c <= 36; c++) {
    const cell = row.getCell(c);
    let v = cell.value;
    if (v && typeof v === 'object' && Array.isArray(v.richText)) {
      v = v.richText.map((t) => t.text).join('');
    }
    const t = String(v || '').trim();
    if (t === ':' || t.startsWith(': ')) return c;
  }
  return fallback;
}

function clearVinFastRightSampleValues(ws, rowNum) {
  const col = findVinFastRightValueCol(ws, rowNum);
  if (col) masterCell(ws, rowNum, col).value = null;
}

function fillRightLabel(ws, labelIncludes, value, { labelMinCol = 17, valueCol = VF_RIGHT_VALUE_COL } = {}) {

  const n = normLabel(labelIncludes);

  const r = findRow(ws, (row) => {

    for (let c = labelMinCol; c <= labelMinCol + 9; c++) {

      const t = normLabel(cellText(row.getCell(c).value));

      if (t === n || t.startsWith(`${n}:`) || t.includes(n)) return true;

    }

    return false;

  });

  if (!r) return false;

  clearVinFastRightSampleValues(ws, r);

  const col = findVinFastRightValueCol(ws, r, valueCol);

  setCell(ws, r, col, value);

  return true;

}



function fillSoPhieuNgay(ws, ctx) {

  const r = findRow(ws, (row) => normLabel(cellText(row.getCell(2).value)).includes('so phieu'));

  if (!r) return;

  setCell(ws, r, 2, `Số phiếu: ${ctx.SO_PHIEU}`);

  if (normLabel(cellText(ws.getRow(r).getCell(17).value)).includes('ngay')) {

    setCell(ws, r, 17, `Ngày tạo : ${ctx.NGAY_TAO}`);

  }

}



function fillVinFastCustomerBlock(ws, ctx, templateKey = 'bao_gia') {

  const qt = templateKey === 'quyet_toan';

  fillSoPhieuNgay(ws, ctx);

  const dyn = { dynamicValueCol: qt, valueCol: qt ? 9 : 7 };

  fillLabelBlock(ws, 'chu xe', ctx.TEN_KH, dyn);

  fillLabelBlock(ws, 'dia chi', ctx.DIA_CHI_KH, dyn);

  fillLabelBlock(ws, 'dien thoai', ctx.SDT_KH_EMAIL, dyn);

  fillLabelBlock(ws, 'nguoi mang xe den', ctx.NGUOI_MANG_XE, dyn);

  fillLabelBlock(ws, 'don vi bao hiem', ctx.DON_VI_BH, dyn);

  fillLabelBlock(ws, 'thoi gian khach hang toi', ctx.THOI_GIAN_DEN, dyn);

  fillLabelBlock(ws, 'thoi gian du kien bat dau', ctx.THOI_GIAN_BAT_DAU, dyn);

  fillLabelBlock(ws, 'yeu cau khach hang', ctx.YEU_CAU_KH, dyn);

  fillLabelBlock(ws, 'muc dich su dung', ctx.MUC_DICH, dyn);

  fillRightLabel(ws, 'bien so', ctx.BIEN_SO);

  fillRightLabel(ws, 'ma kieu xe', ctx.MA_KIEU_XE);

  fillRightLabel(ws, 'so khung', ctx.SO_KHUNG);

  fillRightLabel(ws, 'so km', ctx.SO_KM);

  fillRightLabel(ws, 'ngay kich hoat bao hanh', ctx.NGAY_KICH_HOAT_BH);

}



function fillLenhSuaChuaHeader(ws, ctx) {

  fillVinFastCustomerBlock(ws, ctx);

  const r = findRow(ws, (row) => normLabel(cellText(row.getCell(2).value)).includes('so phieu'));

  if (r) setCell(ws, r, 2, `Số phiếu: ${ctx.SO_PHIEU}     CVDV: ${ctx.CVDV}`);

}



function clearDataRow(ws, rowNum, cols) {

  const toClear = cols?.length ? cols : [];

  for (let c = 2; c <= 25; c++) {

    if (cols?.length && !toClear.includes(c)) continue;

    const cell = masterCell(ws, rowNum, c);

    cell.value = null;

  }

}

/** Dòng «Tổng tiền» ngay sau một section (công việc / phụ tùng). */
function findSectionTotalRow(ws, sectionTitle, maxScan = 120) {
  const sec = normLabel(sectionTitle);
  const secRow = findRow(ws, (row) => {
    for (let c = 1; c <= 24; c++) {
      const t = normLabel(cellText(row.getCell(c).value));
      if (t.includes(sec)) return true;
    }
    return false;
  });
  if (!secRow) return null;

  for (let r = secRow + 1; r <= secRow + maxScan; r++) {
    const row = ws.getRow(r);
    for (let c = 1; c <= 24; c++) {
      const t = normLabel(cellText(row.getCell(c).value));
      if (sec === 'noi dung cong viec' && t === 'phu tung') return null;
    }
    if (rowLabelIncludes(row, 'tong tien', { minCol: 1, maxCol: 12 })) return r;
  }
  return null;
}

/** Ghi tổng section — xóa số mẫu (mẫu quyết toán hay để ở cột 22). */
function writeSectionTotal(ws, tr, total, templateRow, cols) {
  for (const c of cols) masterCell(ws, tr, c).value = null;
  for (const c of cols) setMoneyCell(ws, tr, c, total, templateRow);
}

function footerCols(templateKey) {
  if (templateKey === 'quyet_toan') {
    return { payCol: 8, sumCol: 33, clear: [8, 9, 10, 11, 12, 33, 34, 35, 36, 37] };
  }
  return {
    payCol: 6,
    sumCol: 29,
    clear: [6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 29, 30, 31, 32, 33, 34, 35, 36, 37],
  };
}

function clearFooterMoneyCells(ws, rowNum, templateKey) {
  const { clear } = footerCols(templateKey);
  for (const c of clear) {
    masterCell(ws, rowNum, c).value = null;
  }
}

/** Thành tiền dòng CV/PT trên app đã gồm VAT 8% — tách lại cho footer mẫu VF. */
function calcTotalsFromLines(jobs, parts) {
  const afterVat =
    jobs.reduce((s, j) => s + (Number(j.total) || 0), 0) +
    parts.reduce((s, p) => s + (Number(p.total) || 0), 0);
  const beforeVat = afterVat > 0 ? Math.round(afterVat / 1.08) : 0;
  const vat = afterVat - beforeVat;
  return { beforeVat, vat, afterVat, discount: 0 };
}

function findFooterSumValueCol(ws, rowNum, fallback) {
  const row = ws.getRow(rowNum);
  for (let c = 28; c <= 36; c++) {
    let v = row.getCell(c).value;
    if (v && typeof v === 'object' && Array.isArray(v.richText)) {
      v = v.richText.map((t) => t.text).join('');
    }
    const t = String(v || '').trim();
    if (t === ':' || t.startsWith(': ')) return c;
  }
  return fallback;
}

/** Footer: thanh toán (F/G) + tổng chi phí (cột 29) — xóa số mẫu, không cộng VAT 2 lần. */
function fillCostSummaryFooter(ws, jobs, parts, pay, templateKey = 'bao_gia') {
  const { payCol, sumCol } = footerCols(templateKey);
  const payCols =
    templateKey === 'quyet_toan' ? [8, 9, 10, 11, 12, 13, 14] : [6, 7, 8, 9, 10, 11, 12];
  const sumCols =
    templateKey === 'quyet_toan'
      ? [31, 32, 33, 34, 35, 36, 37]
      : [28, 29, 30, 31, 32, 33, 34, 35];

  const { beforeVat, vat, afterVat, discount } = calcTotalsFromLines(jobs, parts);

  const customer = Number(pay?.customer) || 0;
  const insurance =
    pay?.insurance != null && pay?.insurance !== '' ? Number(pay.insurance) : 0;
  const warranty = Number(pay?.warranty) || 0;
  const internal = Number(pay?.internal) || 0;

  const payRows = [
    ['khach hang thanh toan', customer],
    ['bao hiem thanh toan', insurance],
    ['bao hanh thanh toan', warranty],
    ['noi bo thanh toan', internal],
  ];

  const { start: mergeStart, end: mergeEnd } = payValueMergeCols(templateKey);
  const widthSnapshot = snapshotColumnWidths(ws, mergeStart, mergeEnd);

  for (const [payLabel, payAmt] of payRows) {
    const r = findRow(ws, (row, rowNum) => {
      if (rowNum < 40) return false;
      return rowLabelIncludes(row, payLabel, { minCol: 1, maxCol: 8 });
    });
    if (!r) continue;
    for (const c of payCols) {
      if (c >= mergeStart && c <= mergeEnd) continue;
      masterCell(ws, r, c).value = null;
    }
    setPayFooterCell(ws, r, payCol, payAmt, templateKey, widthSnapshot);
  }

  const costRows = [
    ['tong chi phi truoc gg', beforeVat],
    ['tong chi phi gg', discount],
    ['tong chi phi sau gg', beforeVat - discount],
    ['thue vat', vat],
    ['tong chi phi sau vat', afterVat],
  ];

  for (const [label, amt] of costRows) {
    const r = findRow(ws, (row, rowNum) => {
      if (rowNum < 40) return false;
      for (let c = 20; c <= 32; c++) {
        const t = normLabel(cellText(row.getCell(c).value));
        if (t.includes(label)) return true;
      }
      return false;
    });
    if (!r) continue;
    for (const c of sumCols) masterCell(ws, r, c).value = null;
    const sc = findFooterSumValueCol(ws, r, sumCol);
    setMoneyCell(ws, r, sc, amt, r);
  }
}



/**

 * Thay dòng danh sách — KHÔNG spliceRows (giữ merge toàn sheet).

 */

function replaceListRows(ws, { sectionTitle, headerTest, endTest, items, fillRow, clearCols }) {

  const secRow = findRow(ws, (row) => {

    for (let c = 1; c <= 24; c++) {

      const t = normLabel(cellText(row.getCell(c).value));

      if (t.includes(normLabel(sectionTitle))) return true;

    }

    return false;

  });

  if (!secRow) return;



  let headerRow = null;

  for (let r = secRow + 1; r <= secRow + 10; r++) {

    if (headerTest(ws.getRow(r))) {

      headerRow = r;

      break;

    }

  }

  if (!headerRow) return;



  let dataStart = headerRow + 1;

  if (rowContains(ws, dataStart, 'go') || rowContains(ws, dataStart, 'gò')) dataStart += 1;



  let dataEnd = dataStart;

  for (let r = dataStart; r <= dataStart + 120; r++) {

    if (endTest(ws.getRow(r), r)) {

      dataEnd = r;

      break;

    }

    dataEnd = r + 1;

  }



  const existing = Math.max(0, dataEnd - dataStart);

  const need = items.length;

  const templateRow = dataStart;

  const cols = clearCols || [2, 3, 4, 5, 7, 8, 11, 12, 13, 14, 18, 19];



  if (need > existing) {

    for (let i = 0; i < need - existing; i++) {

      ws.duplicateRow(dataEnd - 1, 1, true);

      dataEnd += 1;

    }

  }



  for (let i = 0; i < need; i++) {

    const rowNum = dataStart + i;

    fillRow(ws, rowNum, items[i], i + 1, templateRow);

    const row = ws.getRow(rowNum);

    row.hidden = false;

    if (ws.getRow(templateRow).height) row.height = ws.getRow(templateRow).height;

  }



  for (let i = need; i < existing; i++) {

    const rowNum = dataStart + i;

    clearDataRow(ws, rowNum);

    ws.getRow(rowNum).hidden = true;

  }

}



function listLayout(templateKey) {
  if (templateKey === 'quyet_toan') {
    return {
      jobs: { stt: 2, code: 5, name: 10, price: 18, total: [22], clear: [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22] },
      parts: { stt: 2, code: 4, name: 10, qty: 16, unit: 17, price: 19, total: [22], clear: [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22] },
      jobsHeader: (row) => {
        const a = normLabel(cellText(row.getCell(2).value));
        const b = normLabel(cellText(row.getCell(5).value));
        return a === 'stt' && b.includes('ma cong');
      },
      partsHeader: (row) => normLabel(cellText(row.getCell(2).value)) === 'stt' && normLabel(cellText(row.getCell(4).value)).includes('ma phu'),
    };
  }
  return {
    jobs: { stt: 2, code: 5, name: 7, price: 13, total: [18], clear: [2, 3, 4, 5, 7, 8, 13, 14, 18, 19, 20] },
    parts: { stt: 3, code: 4, name: 8, qty: 11, unit: 12, price: 14, total: [19], clear: [3, 4, 7, 8, 11, 12, 14, 15, 19, 20] },
    jobsHeader: (row) => {
      const a = normLabel(cellText(row.getCell(2).value));
      const b = normLabel(cellText(row.getCell(5).value));
      return a === 'stt' && b.includes('ma cong');
    },
    partsHeader: (row) => normLabel(cellText(row.getCell(3).value)) === 'stt',
  };
}

function writeLineMoney(ws, rowNum, cols, amount, templateRow) {
  const lineTotal = Number(amount) || 0;
  for (const c of cols) setMoneyCell(ws, rowNum, c, lineTotal, templateRow);
}

function fillJobsList(ws, jobs, templateKey = 'bao_gia') {
  const L = listLayout(templateKey);

  replaceListRows(ws, {
    sectionTitle: 'noi dung cong viec',
    headerTest: L.jobsHeader,
    endTest: (row) => rowLabelIncludes(row, 'tong tien'),
    items: jobs,
    clearCols: L.jobs.clear,
    fillRow: (ws, rowNum, item, stt, templateRow) => {
      setCell(ws, rowNum, L.jobs.stt, stt);
      setCell(ws, rowNum, L.jobs.code, item.code || '');
      setCell(ws, rowNum, L.jobs.name, item.name || '');
      setMoneyCell(ws, rowNum, L.jobs.price, item.price, templateRow);
      writeLineMoney(ws, rowNum, L.jobs.total, item.total, templateRow);
    },
  });

  const total = jobs.reduce((s, j) => s + (Number(j.total) || 0), 0);
  const tr = findSectionTotalRow(ws, 'noi dung cong viec');
  if (tr) writeSectionTotal(ws, tr, total, tr - 1, L.jobs.total);
}

function fillPartsList(ws, parts, templateKey = 'bao_gia') {
  const L = listLayout(templateKey);

  replaceListRows(ws, {
    sectionTitle: 'phu tung',
    headerTest: L.partsHeader,
    endTest: (row) => rowLabelIncludes(row, 'tong tien'),
    items: parts,
    clearCols: L.parts.clear,
    fillRow: (ws, rowNum, item, stt, templateRow) => {
      setCell(ws, rowNum, L.parts.stt, stt);
      setCell(ws, rowNum, L.parts.code, item.code || '');
      setCell(ws, rowNum, L.parts.name, item.name || '');
      setCell(ws, rowNum, L.parts.qty, item.qty ?? 1);
      setCell(ws, rowNum, L.parts.unit, item.unit || 'Cái');
      setMoneyCell(ws, rowNum, L.parts.price, item.price, templateRow);
      writeLineMoney(ws, rowNum, L.parts.total, item.total, templateRow);
    },
  });

  const total = parts.reduce((s, p) => s + (Number(p.total) || 0), 0);
  const tr = findSectionTotalRow(ws, 'phu tung');
  if (tr) writeSectionTotal(ws, tr, total, tr - 1, L.parts.total);
}

/** @deprecated use fillJobsList */
function fillJobsBaoGia(ws, jobs) {
  fillJobsList(ws, jobs, 'bao_gia');
}

/** @deprecated use fillPartsList */
function fillPartsBaoGia(ws, parts) {
  fillPartsList(ws, parts, 'bao_gia');
}



function fillPaymentLines(ws, pay) {
  /* Thanh toán + tổng chi phí ghi trong fillCostSummaryFooter (cột 7 và 29). */
  void ws;
  void pay;
}



function fillPhieuRaCong(ws, ctx) {

  const opts = { valueCol: 3 };

  fillLabelBlock(ws, 'ma lenh sua chua', ctx.SO_PHIEU, opts);

  fillLabelBlock(ws, 'ngay tao', ctx.NGAY_TAO, opts);

  fillLabelBlock(ws, 'bien so xe', ctx.BIEN_SO, opts);

  fillLabelBlock(ws, 'ma kieu xe', ctx.MA_KIEU_XE, opts);

  fillLabelBlock(ws, 'khach hang', ctx.TEN_KH, opts);

  fillLabelBlock(ws, 'dia chi', ctx.DIA_CHI_KH, opts);

  fillLabelBlock(ws, 'so khung xe', ctx.SO_KHUNG, opts);

  fillLabelBlock(ws, 'mau xe', ctx.MAU_XE, opts);

  fillLabelBlock(ws, 'ngay ra cong', ctx.NGAY_RA_CONG, opts);

}



function fillPhieuTiepNhan(ws, ctx) {

  const rSo = findRow(ws, (row) => normLabel(cellText(row.getCell(1).value)).includes('so phieu'));

  if (rSo) {

    setCell(ws, rSo, 2, ctx.SO_PHIEU);

    setCell(ws, rSo, 4, ctx.NGAY_TAO);

  }



  const leftRight = [

    { left: 'ho ten khach hang', val: ctx.TEN_KH, right: 'bien so', rval: ctx.BIEN_SO },

    { left: 'dia chi', val: ctx.DIA_CHI_KH, right: 'ma kieu xe', rval: ctx.MA_KIEU_XE },

    { left: 'dien thoai', val: ctx.SDT_KH, right: 'so khung', rval: ctx.SO_KHUNG },

    { left: 'cong ty', val: ctx.TEN_CONG_TY_KH, right: 'so may', rval: ctx.SO_MAY },

    { left: 'nguoi mang xe den', val: ctx.NGUOI_MANG_XE, right: 'so km', rval: ctx.SO_KM },

  ];



  for (const item of leftRight) {

    const r = findRow(ws, (row) => normLabel(cellText(row.getCell(1).value)).includes(normLabel(item.left)));

    if (!r) continue;

    setCell(ws, r, 2, item.val);

    for (let c = 4; c <= 14; c++) {

      const t = normLabel(cellText(ws.getRow(r).getCell(c).value));

      if (t.includes(normLabel(item.right))) {

        setCell(ws, r, c + 1, item.rval);

        break;

      }

    }

  }



  const rDt = findRow(ws, (row) => {

    const t = normLabel(cellText(row.getCell(1).value));

    return t.includes('dien thoai') && row.number > 8;

  });

  if (rDt) {

    setCell(ws, rDt, 2, ctx.SDT_NGUOI_MANG);

    for (let c = 4; c <= 14; c++) {

      const t = normLabel(cellText(ws.getRow(rDt).getCell(c).value));

      if (t.includes('vach xang') || t.includes('pin')) {

        setCell(ws, rDt, c + 1, ctx.VACH_XANG);

        break;

      }

    }

  }



  fillLabelBlock(ws, 'cong ty bao hiem', ctx.DON_VI_BH, { valueCol: 2 });

  const rTime = findRow(ws, (row) => normLabel(cellText(row.getCell(1).value)).includes('thoi gian nhan xe'));

  if (rTime) setCell(ws, rTime, 2, ctx.THOI_GIAN_NHAN);

  const rYc = findRow(ws, (row) => normLabel(cellText(row.getCell(1).value)).includes('yeu cau cua khach'));

  if (rYc) setCell(ws, rYc, 2, ctx.YEU_CAU_KH);

}



export function setCompanyHeader(ws, companyName) {

  if (!companyName) return;

  const lines = String(companyName).split('\n').filter(Boolean);

  const title = lines[0] || companyName;

  const sub = lines[1] || '';

  for (let r = 1; r <= 4; r++) {

    const row = ws.getRow(r);

    for (let c = 1; c <= 12; c++) {

      const t = cellText(row.getCell(c).value);

      if (t && (t.includes('CÔNG TY') || t.includes('VinFast') || t.includes('Vinfast'))) {

        setCell(ws, r, c, title);

        if (sub) {

          const r2 = r + 1;

          if (r2 <= 5) setCell(ws, r2, c, sub);

        }

        return;

      }

    }

  }

}



/** Trích số khung / km / kiểu xe từ ghi chú & vehicle_activity (WO VinFast). */
export function extractVehicleFields(row) {
  const plate = String(row.bien_so || '').trim().toUpperCase();
  const activity = String(row.vehicle_activity || row.vehicle_activity_note || '').trim();
  const blob = [row.urgent_note, row.customer_note, activity, row.payment_info]
    .filter((x) => x != null && x !== '')
    .map((x) => (typeof x === 'object' ? JSON.stringify(x) : String(x)))
    .join('\n');

  let soKhung = String(row.so_khung || row.vin || row.vehicle_vin || '').trim();
  if (!soKhung) {
    const vin = blob.match(/\b([A-HJ-NPR-Z0-9]{17})\b/i);
    if (vin) soKhung = vin[1].toUpperCase();
  }

  let soKm = String(row.so_km || row.km || '').trim();
  if (!soKm) {
    const km =
      blob.match(/(?:so\s*km|số\s*km|km)\s*[:：]?\s*([\d.,]+)/i) ||
      blob.match(/([\d.,]+)\s*km\b/i);
    if (km) soKm = km[1].replace(/\./g, '').replace(/,/g, '');
  }

  let model = '';
  const vf = blob.match(/\b(VF\s*\d+\s*(?:Plus|City)?|VF\d+)\b/i);
  if (vf) model = vf[1].replace(/\s+/g, ' ').trim();
  else if (/^vf\s*\d/i.test(activity) && activity.length < 40) model = activity;

  let ngayBh = '';
  const d = blob.match(/(?:kich hoat|kích hoạt|bao hanh|bảo hành)[^\d]{0,20}(\d{4}[\/\-]\d{1,2}[\/\-]\d{1,2})/i);
  if (d) ngayBh = d[1].replace(/-/g, '/');

  return { plate, soKhung, soKm, model, ngayBh };
}

export function buildVinFastContext(row, workshopDefaults = {}) {

  const veh = extractVehicleFields(row);
  const activity = String(row.vehicle_activity || row.vehicle_activity_note || '').trim();
  const wo = String(row.cvdv_wo_code || row.ro_code || '').trim();

  const timeIn = row.time_in || row.created_at;

  const noteRaw = String(row.urgent_note || row.customer_note || '').trim();

  const addrRaw = String(row.customer_note || '').trim();

  const addrLooksLikeTags = /^\[|NỢ KHÁCH|BH:/i.test(addrRaw);

  const customerDisplayName = (() => {
    const name = String(row.customer_name || '').trim();
    const linked = String(row.linked_customer || '').trim();
    if (name && !/^\[|NỢ KHÁCH/i.test(name)) return name;
    if (linked) return linked;
    return name;
  })();

  const yeuCauKh = noteRaw
    .replace(/\[BH:[^\]]*\]/gi, '')
    .replace(/\[NỢ KHÁCH[^\]]*\]/gi, '')
    .trim();



  let pi = row.payment_info;

  if (typeof pi === 'string') {

    try {

      pi = JSON.parse(pi);

    } catch {

      pi = {};

    }

  }

  if (!pi || typeof pi !== 'object') pi = {};

  const pick = (...keys) => {

    for (const k of keys) {

      let v = pi[k];

      if (v == null || v === '') v = row[k];

      if (v != null && v !== '') return Number(v) || 0;

    }

    return 0;

  };



  let insuranceCo = '';

  const m = noteRaw.match(/\[BH:\s*([^\]]+)\]/i);

  if (m) insuranceCo = m[1].trim();

  else if (pi.insurance_company) insuranceCo = String(pi.insurance_company).trim();



  const companyName =

    workshopDefaults.company_name ||

    process.env.WORKSHOP_NAME ||

    'CÔNG TY TNHH HUNTER MAI LINH\nVinFast Hunter Mai Linh XDV';

  const companyLines = String(companyName).split('\n').filter(Boolean);
  const addrLine =
    workshopDefaults.company_address ||
    (companyLines.length > 2 ? companyLines.slice(1, -1).join('\n') : companyLines[1] || '');
  const phoneLine = workshopDefaults.company_phone || '';



  return {

    TEN_CONG_TY: companyName,
    COMPANY_ADDRESS: addrLine,
    COMPANY_PHONE: phoneLine,

    SO_PHIEU: wo,

    NGAY_TAO: fmtVnDateSlash(timeIn || new Date()),

    NGAY_RA_CONG: fmtVnDateSlash(row.time_out || new Date()),

    TEN_KH: customerDisplayName,

    DIA_CHI_KH: addrLooksLikeTags ? '' : String(addrRaw || ''),

    SDT_KH: row.customer_phone || '',

    SDT_KH_EMAIL: row.customer_phone

      ? `${row.customer_phone}${noteRaw.includes('@') ? `       Email:${noteRaw.match(/[\w.+-]+@[\w.-]+/)?.[0] || ''}` : ''}`

      : '',

    NGUOI_MANG_XE: customerDisplayName,

    SDT_NGUOI_MANG: row.customer_phone || '',

    DON_VI_BH: insuranceCo,

    THOI_GIAN_DEN: fmtVnDateTime(timeIn),

    THOI_GIAN_BAT_DAU: fmtVnDateTime(timeIn),

    THOI_GIAN_NHAN: fmtVnDateTime(timeIn),

    YEU_CAU_KH: noteRaw,

    MUC_DICH: 'Cá nhân',

    BIEN_SO: veh.plate || row.bien_so || '',

    MA_KIEU_XE:
      veh.model ||
      (/^vf\s*\d/i.test(activity) && activity.length < 40 ? activity : ''),

    SO_KHUNG: veh.soKhung,

    SO_KM: veh.soKm,

    NGAY_KICH_HOAT_BH: veh.ngayBh,

    SO_MAY: '',

    VACH_XANG: '',

    MAU_XE: '',

    TEN_CONG_TY_KH: '',

    CVDV: row.cvdv_username || '',

    KTV: row.ktv_username || '',

    pay: {

      customer: pick('customer_pay', 'customerPay'),

      insurance: pick('insurance_pay', 'insurancePay'),

      warranty: pick('warranty_pay', 'warrantyPay'),

      internal: pick('debt', 'cong_no'),

    },

  };

}



function pickLineName(item) {
  for (const key of ['name', 'ten', 'part_name', 'mo_ta', 'description']) {
    const v = item[key];
    if (v == null || v === '') continue;
    if (typeof v === 'number') continue;
    const s = String(v).trim();
    if (!s) continue;
    if (/^[\d,.\s]+$/.test(s)) continue;
    return s;
  }
  return '';
}

export function mapJobsFromRow(row) {

  let jobs = row.jobs;

  if (typeof jobs === 'string') {

    try {

      jobs = JSON.parse(jobs);

    } catch {

      jobs = [];

    }

  }

  if (!Array.isArray(jobs)) return [];

  return jobs.map((j, i) => {

    const qty = Number(j.qty ?? j.hours ?? 1) || 1;

    const price = Number(j.price ?? j.don_gia ?? 0) || 0;

    const total = Number(j.total ?? j.totalWithVat ?? qty * price) || qty * price;

    return {

      stt: i + 1,

      code: String(j.code ?? j.ma ?? '').trim(),

      name: pickLineName(j),

      qty,

      price,

      total,

    };

  });

}



export function mapPartsFromRow(row) {

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

    const price = Number(p.price ?? p.don_gia ?? 0) || 0;

    const total = Number(p.total ?? p.totalWithVat ?? qty * price) || qty * price;

    return {

      stt: i + 1,

      code: String(p.code ?? p.ma ?? '').trim(),

      name: pickLineName(p),

      qty,

      unit: 'Cái',

      price,

      total,

    };

  });

}



export function fillVinFastTemplate(ws, templateKey, row, workshopDefaults = {}) {

  const ctx = buildVinFastContext(row, workshopDefaults);

  setCompanyHeader(ws, ctx.TEN_CONG_TY);



  const jobs = mapJobsFromRow(row);

  const parts = mapPartsFromRow(row);



  switch (templateKey) {

    case 'bao_gia':

      fillVinFastCustomerBlock(ws, ctx, 'bao_gia');

      fillJobsList(ws, jobs, 'bao_gia');

      fillPartsList(ws, parts, 'bao_gia');

      fillCostSummaryFooter(ws, jobs, parts, ctx.pay, 'bao_gia');

      break;

    case 'lenh_sua_chua':
      fillLenhSuaChuaVinFast(ws, row, workshopDefaults);
      break;

    case 'quyet_toan':

      fillVinFastCustomerBlock(ws, ctx, 'quyet_toan');

      fillJobsList(ws, jobs, 'quyet_toan');

      fillPartsList(ws, parts, 'quyet_toan');

      fillCostSummaryFooter(ws, jobs, parts, ctx.pay, 'quyet_toan');

      break;

    case 'phieu_ra_cong':

      fillPhieuRaCong(ws, ctx);

      break;

    case 'phieu_tiep_nhan':

      fillPhieuTiepNhan(ws, ctx);

      break;

    default:

      break;

  }

}


