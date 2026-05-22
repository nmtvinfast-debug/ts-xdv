/**
 * Sửa tên sheet lỗi trong mẫu Phiếu yêu cầu PT (ký tự `{` gây Excel báo repair).
 */
import ExcelJS from 'exceljs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const file = path.join(__dirname, '../templates/TS_PHIEU_YEU_CAU_PHU_TUNG_VF_TEMPLATE.xlsx');

const wb = new ExcelJS.Workbook();
await wb.xlsx.readFile(file);
for (const ws of wb.worksheets) {
  const name = String(ws.name || '');
  if (/^\{?[0-9a-f]{8}-/i.test(name) || /[\[\]\:\/\?\*\\]/.test(name)) {
    ws.name = 'PhieuYeuCauPT';
  }
}
await wb.xlsx.writeFile(file);
console.log('Fixed sheet name in', file);
