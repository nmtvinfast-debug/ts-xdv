import express from 'express';
import {
  DOCUMENT_TEMPLATES,
  documentDownloadFilename,
  listTemplateAvailability,
  renderDocumentFromTemplate,
} from '../lib/excel_template_export.js';
import { parseBearerTokenId } from '../lib/ro_time_rules.js';

export function createDocumentsRouter(pool) {
  const r = express.Router();

  r.get('/templates', (req, res) => {
    const items = listTemplateAvailability();
    res.json({
      ok: items.every((t) => t.exists),
      templates: items.map(({ key, file, exists }) => ({ key, file, exists })),
    });
  });

  /** GET /api/v1/documents/export/:templateKey/:repairOrderId — không bắt buộc đăng nhập. */
  r.get('/export/:templateKey/:repairOrderId', async (req, res) => {
    const { templateKey, repairOrderId } = req.params;
    if (!DOCUMENT_TEMPLATES[templateKey]) {
      return res.status(400).json({
        error: 'templateKey không hợp lệ',
        allowed: Object.keys(DOCUMENT_TEMPLATES),
      });
    }

    try {
      const actorId = parseBearerTokenId(req);
      if (actorId) {
        const ures = await pool.query(
          `SELECT id FROM users WHERE id = $1 AND COALESCE(is_active, true) = true`,
          [actorId],
        );
        if (ures.rowCount === 0) {
          return res.status(401).json({ error: 'Token không hợp lệ — đăng nhập lại' });
        }
      }

      const roRes = await pool.query(`SELECT * FROM repair_orders WHERE id = $1`, [repairOrderId]);
      if (roRes.rowCount === 0) return res.status(404).json({ error: 'Không tìm thấy RO' });

      const setRes = await pool.query(`SELECT workshop_defaults FROM app_settings WHERE id = 1`);
      const workshop =
        setRes.rows[0]?.workshop_defaults && typeof setRes.rows[0].workshop_defaults === 'object'
          ? setRes.rows[0].workshop_defaults
          : {};

      const wb = await renderDocumentFromTemplate(templateKey, roRes.rows[0], workshop);
      const buffer = await wb.xlsx.writeBuffer();
      const filename = documentDownloadFilename(
        templateKey,
        roRes.rows[0].bien_so,
        roRes.rows[0].ro_code,
      );

      res.setHeader(
        'Content-Type',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
      res.send(Buffer.from(buffer));
    } catch (err) {
      console.error('[documents/export]', err);
      res.status(500).json({ error: err.message || 'Lỗi xuất mẫu Excel' });
    }
  });

  return r;
}
