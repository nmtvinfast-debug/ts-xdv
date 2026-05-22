/**

 * Điền mẫu Excel TS cũ dùng {{PLACEHOLDER}} (phiếu PT, hóa đơn nội bộ…).

 */

import { buildVinFastContext } from './vf_excel_fill.js';



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



function setCellPlain(cell, text) {

  cell.value = text == null ? '' : String(text);

}



export function buildPlaceholderContext(row, workshopDefaults = {}) {

  const vf = buildVinFastContext(row, workshopDefaults);

  const companyLines = String(vf.TEN_CONG_TY || '').split('\n');

  const wd = workshopDefaults && typeof workshopDefaults === 'object' ? workshopDefaults : {};



  return {

    TEN_CONG_TY: companyLines[0] || wd.company_name || 'TS-XDV AUTO SERVICE',

    DIA_CHI: wd.address || wd.dia_chi || process.env.WORKSHOP_ADDRESS || '',

    SO_DIEN_THOAI: wd.phone || wd.so_dien_thoai || process.env.WORKSHOP_PHONE || '',

    MST: wd.tax_code || wd.mst || process.env.WORKSHOP_TAX_CODE || '',

    LENH_SUA_CHUA: vf.SO_PHIEU,

    SO_HD: vf.SO_PHIEU,

    NGAY: vf.NGAY_TAO,

    TEN_KH: vf.TEN_KH,

    BIEN_SO: vf.BIEN_SO,

    KTV: vf.KTV,

    CVDV: vf.CVDV,

    TRANG_THAI: String(row.status || '').replace(/_/g, ' '),

    DIA_CHI_KH: vf.DIA_CHI_KH,

    SDT_KH: vf.SDT_KH,

    RO_CODE: String(row.ro_code || '').trim(),

  };

}



export function fillPlaceholderTemplate(ws, ctx) {

  const keys = Object.keys(ctx).sort((a, b) => b.length - a.length);

  ws.eachRow((row) => {

    row.eachCell((cell) => {

      let text = cellText(cell.value);

      if (!text.includes('{{')) return;

      for (const key of keys) {

        const val = ctx[key] == null ? '' : String(ctx[key]);

        text = text.split(`{{${key}}}`).join(val);

      }

      setCellPlain(cell, text);

    });

  });

}


