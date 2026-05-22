import express from 'express';
import multer from 'multer';
import XLSX from 'xlsx';
import { buildMaintenanceReminders } from '../lib/maintenance_reminder.js';
import {
  parseInvoiceUploadRows,
  buildInvoiceTrackingReport,
  buildVehicleInvoiceStatus,
  buildStockAvailableMap,
  deductInvoiceStockItems,
  getIssuedRoIdSet,
  normalizePartCode,
} from '../lib/invoice_tracking.js';
import { buildInvoiceVehicleWorkbook } from '../lib/invoice_export.js';

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 15 * 1024 * 1024 } });

export function createExtrasRouter(pool) {
  const r = express.Router();

  /** GET /api/v1/extras/maintenance-reminders */
  r.get('/maintenance-reminders', async (req, res) => {
    try {
      const phone = String(req.query.phone || '').trim();
      const roRes = await pool.query(
        `SELECT id, ro_code, bien_so, customer_name, customer_phone, vehicle_activity,
                status, time_in, time_out, time_done, created_at, linked_customer
         FROM repair_orders
         ORDER BY time_in DESC NULLS LAST`,
      );
      let rows = roRes.rows;
      if (phone) {
        const p = phone.replace(/\D/g, '');
        rows = rows.filter((ro) => String(ro.customer_phone || '').replace(/\D/g, '').includes(p));
      }
      const list = buildMaintenanceReminders(rows, { includeAllStatuses: false });
      res.json({ reminders: list, total: list.length });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  /** GET /api/v1/extras/invoice-tracking */
  r.get('/invoice-tracking', async (req, res) => {
    try {
      const setRes = await pool.query(`SELECT workshop_defaults FROM app_settings WHERE id = 1`);
      const wd = setRes.rows[0]?.workshop_defaults || {};
      const uploaded = wd.invoice_pt_upload?.items || [];
      const issuedIds = getIssuedRoIdSet(wd);

      const roRes = await pool.query(
        `SELECT * FROM repair_orders WHERE parts IS NOT NULL AND parts::text NOT IN ('[]','null')
         ORDER BY time_in DESC NULLS LAST`,
      );
      let invRes = { rows: [] };
      try {
        invRes = await pool.query(
          `SELECT part_code, name, price_in, price_out, unit FROM inventory_items`,
        );
      } catch {
        /* inventory optional */
      }

      const report = buildInvoiceTrackingReport(roRes.rows, uploaded, invRes.rows, issuedIds);
      res.json({
        ...report,
        last_upload_at: wd.invoice_pt_upload?.uploaded_at || null,
      });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  /** POST /api/v1/extras/invoice-tracking/upload — multipart field `file` */
  r.post('/invoice-tracking/upload', upload.single('file'), async (req, res) => {
    try {
      if (!req.file?.buffer?.length) {
        return res.status(400).json({ error: 'Thiếu file Excel' });
      }
      const wb = XLSX.read(req.file.buffer, { type: 'buffer' });
      const sheet = wb.Sheets[wb.SheetNames[0]];
      const rows = XLSX.utils.sheet_to_json(sheet, { header: 1, defval: '' });
      const items = parseInvoiceUploadRows(rows);
      if (items.length === 0) {
        return res.status(400).json({ error: 'Không đọc được mã phụ tùng trong file' });
      }

      const payload = {
        uploaded_at: new Date().toISOString(),
        file_name: req.file.originalname || 'upload.xlsx',
        items,
      };

      const cur = await pool.query(`SELECT workshop_defaults FROM app_settings WHERE id = 1`);
      const wd0 =
        cur.rows[0]?.workshop_defaults && typeof cur.rows[0].workshop_defaults === 'object'
          ? { ...cur.rows[0].workshop_defaults }
          : {};
      wd0.invoice_pt_upload = payload;
      await pool.query(
        `INSERT INTO app_settings (id, workshop_defaults) VALUES (1, $1::jsonb)
         ON CONFLICT (id) DO UPDATE SET workshop_defaults = $1::jsonb, updated_at = NOW()`,
        [JSON.stringify(wd0)],
      );

      const roRes = await pool.query(
        `SELECT * FROM repair_orders WHERE parts IS NOT NULL AND parts::text NOT IN ('[]','null')`,
      );
      let invRes = { rows: [] };
      try {
        invRes = await pool.query(`SELECT part_code, name, price_in, price_out, unit FROM inventory_items`);
      } catch {
        /* ignore */
      }

      const issuedIds = getIssuedRoIdSet(wd0);
      const report = buildInvoiceTrackingReport(roRes.rows, items, invRes.rows, issuedIds);
      res.json({
        message: `Đã thay thế dữ liệu cũ — nạp ${items.length} mã hàng từ file tồn kho`,
        ...report,
        last_upload_at: payload.uploaded_at,
        file_name: payload.file_name,
      });
    } catch (err) {
      console.error('[invoice-upload]', err);
      res.status(500).json({ error: err.message });
    }
  });

  /** POST /api/v1/extras/invoice-tracking/mark-issued/:roId — kế toán xác nhận đã xuất HĐ */
  r.post('/invoice-tracking/mark-issued/:roId', async (req, res) => {
    try {
      const roId = String(req.params.roId);
      const fullRo = await pool.query(`SELECT * FROM repair_orders WHERE id = $1`, [roId]);
      if (fullRo.rowCount === 0) return res.status(404).json({ error: 'Không tìm thấy RO' });

      const cur = await pool.query(`SELECT workshop_defaults FROM app_settings WHERE id = 1`);
      const wd0 =
        cur.rows[0]?.workshop_defaults && typeof cur.rows[0].workshop_defaults === 'object'
          ? { ...cur.rows[0].workshop_defaults }
          : {};
      const uploaded = wd0.invoice_pt_upload?.items || [];
      const issuedIds = getIssuedRoIdSet(wd0);
      if (issuedIds.has(roId)) {
        return res.status(400).json({ error: 'RO này đã được đánh dấu xuất hóa đơn.' });
      }

      const allRos = await pool.query(
        `SELECT * FROM repair_orders WHERE parts IS NOT NULL AND parts::text NOT IN ('[]','null')`,
      );
      let invRes = { rows: [] };
      try {
        invRes = await pool.query(`SELECT part_code, name, price_in, price_out, unit FROM inventory_items`);
      } catch {
        /* ignore */
      }
      const report = buildInvoiceTrackingReport(allRos.rows, uploaded, invRes.rows, issuedIds);
      const vehicle = report.vehicles.find((v) => String(v.ro_id) === roId);
      if (!vehicle?.parts_ready) {
        return res.status(400).json({
          error: vehicle?.stock_sufficient === false
            ? 'Không đủ tồn kho file upload cho các mã PT trên xe này (xe khác có thể đã giữ tồn).'
            : 'Xe chưa đủ điều kiện xuất hóa đơn (thiếu mã PT trong file tồn kho).',
        });
      }

      let parts = fullRo.rows[0].parts || [];
      if (typeof parts === 'string') {
        try {
          parts = JSON.parse(parts);
        } catch {
          parts = [];
        }
      }
      if (!Array.isArray(parts)) parts = [];
      if (wd0.invoice_pt_upload) {
        wd0.invoice_pt_upload = {
          ...wd0.invoice_pt_upload,
          items: deductInvoiceStockItems(uploaded, parts),
        };
      }

      if (!wd0.invoice_issued_ro_ids || typeof wd0.invoice_issued_ro_ids !== 'object') {
        wd0.invoice_issued_ro_ids = {};
      }
      wd0.invoice_issued_ro_ids[roId] = {
        at: new Date().toISOString(),
        by: String(req.body?.username || req.body?.by || ''),
      };
      await pool.query(
        `INSERT INTO app_settings (id, workshop_defaults) VALUES (1, $1::jsonb)
         ON CONFLICT (id) DO UPDATE SET workshop_defaults = $1::jsonb, updated_at = NOW()`,
        [JSON.stringify(wd0)],
      );

      const invMap = new Map((wd0.invoice_pt_upload?.items || []).map((it) => [normalizePartCode(it.code), it]));
      const stockMap = new Map();
      for (const it of invRes.rows) {
        const c = normalizePartCode(it.part_code);
        if (c) stockMap.set(c, it);
      }
      const issuedAfter = getIssuedRoIdSet(wd0);

      res.json({
        message: 'Đã chuyển sang «Đã xuất hóa đơn» và trừ tồn kho file upload',
        vehicle: buildVehicleInvoiceStatus(fullRo.rows[0], invMap, stockMap, issuedAfter),
      });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  /** GET /api/v1/extras/invoice-tracking/vehicle/:roId */
  r.get('/invoice-tracking/vehicle/:roId', async (req, res) => {
    try {
      const roRes = await pool.query(`SELECT * FROM repair_orders WHERE id = $1`, [req.params.roId]);
      if (roRes.rowCount === 0) return res.status(404).json({ error: 'Không tìm thấy RO' });

      const setRes = await pool.query(`SELECT workshop_defaults FROM app_settings WHERE id = 1`);
      const wd = setRes.rows[0]?.workshop_defaults || {};
      const uploaded = wd.invoice_pt_upload?.items || [];
      let invRes = { rows: [] };
      try {
        invRes = await pool.query(`SELECT part_code, name, price_in, price_out, unit FROM inventory_items`);
      } catch {
        /* ignore */
      }

      const issuedIds = getIssuedRoIdSet(wd);
      const invMap = new Map(uploaded.map((it) => [normalizePartCode(it.code), it]));
      const stockMap = new Map();
      for (const it of invRes.rows) {
        const c = normalizePartCode(it.part_code);
        if (c) stockMap.set(c, it);
      }
      res.json(buildVehicleInvoiceStatus(roRes.rows[0], invMap, stockMap, issuedIds));
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  /** GET /api/v1/extras/invoice-tracking/export/:roId — Excel chi tiết HĐ theo xe */
  r.get('/invoice-tracking/export/:roId', async (req, res) => {
    try {
      const roRes = await pool.query(`SELECT * FROM repair_orders WHERE id = $1`, [req.params.roId]);
      if (roRes.rowCount === 0) return res.status(404).json({ error: 'Không tìm thấy RO' });

      const setRes = await pool.query(`SELECT workshop_defaults FROM app_settings WHERE id = 1`);
      const wd = setRes.rows[0]?.workshop_defaults || {};
      const uploaded = wd.invoice_pt_upload?.items || [];

      let invRes = { rows: [] };
      try {
        invRes = await pool.query(`SELECT part_code, name, price_in, price_out, unit FROM inventory_items`);
      } catch {
        /* ignore */
      }

      const wb = await buildInvoiceVehicleWorkbook(roRes.rows[0], uploaded, invRes.rows);
      const buffer = await wb.xlsx.writeBuffer();
      const plate = String(roRes.rows[0].bien_so || 'xe').replace(/[^\w\-]/g, '_');
      const filename = `TheoDoiHD_${plate}_${roRes.rows[0].ro_code || 'RO'}.xlsx`;

      res.setHeader(
        'Content-Type',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
      res.send(Buffer.from(buffer));
    } catch (err) {
      console.error('[invoice-export]', err);
      res.status(500).json({ error: err.message });
    }
  });

  return r;
}
