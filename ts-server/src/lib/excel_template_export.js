import ExcelJS from 'exceljs';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { enrichRepairOrderRow } from './ro_time_rules.js';
import { buildPlaceholderContext, fillPlaceholderTemplate } from './excel_placeholder_fill.js';
import { fillVinFastTemplate } from './vf_excel_fill.js';
import { fillPhieuYeuCauPtVinFast, normalizePtWorksheet } from './vf_excel_phieu_yeu_cau_pt.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const TEMPLATES_DIR = path.join(__dirname, '../../templates');

/** Khóa API → file mẫu VinFast trong `ts-server/templates/` */
export const DOCUMENT_TEMPLATES = {
  phieu_tiep_nhan: 'TS_PHIEU_TIEP_NHAN_VF_TEMPLATE.xlsx',
  bao_gia: 'TS_BAO_GIA_VF_TEMPLATE.xlsx',
  lenh_sua_chua: 'TS_LENH_SUA_CHUA_VF_TEMPLATE.xlsx',
  quyet_toan: 'TS_QUYET_TOAN_VF_TEMPLATE.xlsx',
  phieu_ra_cong: 'TS_PHIEU_RA_CONG_VF_TEMPLATE.xlsx',
  phieu_yeu_cau_pt: 'TS_PHIEU_YEU_CAU_PHU_TUNG_VF_TEMPLATE.xlsx',
  hoa_don_noi_bo: 'TS_HOA_DON_NOI_BO_TEMPLATE.xlsx',
};

const VF_TEMPLATE_KEYS = new Set([
  'phieu_tiep_nhan',
  'bao_gia',
  'lenh_sua_chua',
  'quyet_toan',
  'phieu_ra_cong',
]);

/**
 * @param {'phieu_tiep_nhan'|'bao_gia'|'lenh_sua_chua'|'quyet_toan'|'phieu_ra_cong'|...} templateKey
 */
export function templateFilePath(templateKey) {
  const file = DOCUMENT_TEMPLATES[templateKey];
  if (!file) return null;
  return path.join(TEMPLATES_DIR, file);
}

export function listTemplateAvailability() {
  return Object.entries(DOCUMENT_TEMPLATES).map(([key, file]) => {
    const full = path.join(TEMPLATES_DIR, file);
    return { key, file, exists: fs.existsSync(full) };
  });
}

/** Làm sạch workbook trước khi ghi — tránh XML lỗi khi xuất nhiều lần. */
export function sanitizeWorkbookForWrite(wb) {
  for (const ws of wb.worksheets) {
    const name = String(ws.name || 'Sheet1')
      .replace(/[\[\]\:\/\?\*\\]/g, '')
      .slice(0, 31);
    ws.name = name || 'Sheet1';
    ws.state = 'visible';
  }
}

export async function renderDocumentFromTemplate(templateKey, repairOrderRow, workshopDefaults = {}) {
  const file = DOCUMENT_TEMPLATES[templateKey];
  if (!file) throw new Error(`Mẫu không hỗ trợ: ${templateKey}`);

  const fullPath = path.join(TEMPLATES_DIR, file);
  if (!fs.existsSync(fullPath)) {
    throw new Error(`Thiếu file mẫu trên máy chủ: ${file}. Cần deploy ts-server kèm thư mục templates/.`);
  }

  const row = enrichRepairOrderRow(repairOrderRow);
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.readFile(fullPath);

  for (const sheet of wb.worksheets) {
    if (templateKey === 'phieu_yeu_cau_pt') normalizePtWorksheet(sheet);
  }

  const ws = wb.worksheets[0];
  if (!ws) throw new Error('File mẫu không có sheet');

  try {
    if (templateKey === 'phieu_yeu_cau_pt') {
      fillPhieuYeuCauPtVinFast(ws, row, workshopDefaults);
    } else if (VF_TEMPLATE_KEYS.has(templateKey)) {
      fillVinFastTemplate(ws, templateKey, row, workshopDefaults);
    } else {
      fillPlaceholderTemplate(ws, buildPlaceholderContext(row, workshopDefaults));
    }
  } catch (err) {
    throw new Error(`Lỗi điền dữ liệu mẫu ${templateKey}: ${err.message || err}`);
  }

  sanitizeWorkbookForWrite(wb);
  return wb;
}

export function documentDownloadFilename(templateKey, bienSo, roCode) {
  const plate = String(bienSo || 'xe').replace(/[^\w\-]/g, '_');
  const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const names = {
    phieu_tiep_nhan: 'PhieuTiepNhanVF',
    bao_gia: 'BaoGia',
    phieu_yeu_cau_pt: 'PhieuYeuCauPT',
    quyet_toan: 'QuyetToan',
    hoa_don_noi_bo: 'HoaDonNoiBo',
    lenh_sua_chua: 'LenhSuaChua',
    phieu_ra_cong: 'PhieuRaCong',
  };
  return `${names[templateKey] || templateKey}_${plate}_${stamp}.xlsx`;
}
