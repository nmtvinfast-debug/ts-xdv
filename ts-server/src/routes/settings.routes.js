import express from 'express';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import multer from 'multer';

import { DEFAULT_WORKSHOP_DEFAULTS } from '../lib/default_sla.js';
import { mergeWorkshopDefaults } from '../lib/kh_ads_config.js';
import { createAuthMiddleware, normRole } from '../middleware/user_permissions.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const khAdsUploadDir = path.join(__dirname, '..', '..', 'uploads', 'kh_ads');
fs.mkdirSync(khAdsUploadDir, { recursive: true });

const uploadKhAdImage = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, khAdsUploadDir),
    filename: (_req, file, cb) => {
      const ext = path.extname(file.originalname || '').toLowerCase() || '.jpg';
      const safe = ['.jpg', '.jpeg', '.png', '.webp', '.gif'].includes(ext) ? ext : '.jpg';
      cb(null, `kh_${Date.now()}_${Math.random().toString(36).slice(2, 9)}${safe}`);
    },
  }),
  limits: { fileSize: 8 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const ok = /^image\/(jpeg|png|webp|gif)$/i.test(file.mimetype || '');
    cb(ok ? null : new Error('Chỉ chấp nhận ảnh JPEG/PNG/WebP/GIF'), ok);
  },
});

function deepMergeWorkshop(prev, patch) {
  const next = { ...DEFAULT_WORKSHOP_DEFAULTS, ...prev };
  for (const [k, v] of Object.entries(patch)) {
    if (v != null && typeof v === 'object' && !Array.isArray(v) && typeof next[k] === 'object' && !Array.isArray(next[k])) {
      next[k] = { ...next[k], ...v };
    } else {
      next[k] = v;
    }
  }
  return mergeWorkshopDefaults(next);
}

export function createSettingsRouter(pool) {
  const r = express.Router();
  const auth = createAuthMiddleware(pool);

  r.get('/workshop', async (req, res) => {
    try {
      const result = await pool.query(`SELECT workshop_defaults, updated_at FROM app_settings WHERE id = 1`);
      const row = result.rows[0];
      const merged = deepMergeWorkshop(
        typeof row?.workshop_defaults === 'object' && row.workshop_defaults ? row.workshop_defaults : {},
        {},
      );
      res.json({ workshop_defaults: merged, updated_at: row?.updated_at ?? null });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  const COMPANY_PATCH_KEYS = new Set(['company_name', 'company_address', 'company_phone']);

  r.patch('/workshop', auth, async (req, res) => {
    const role = normRole(req.user.role);
    const patch = req.body?.workshop_defaults ?? req.body;
    if (patch == null || typeof patch !== 'object') {
      return res.status(400).json({ error: 'Thiếu workshop_defaults (object JSON)' });
    }

    let effectivePatch = patch;
    if (role === 'GIAMDOC') {
      effectivePatch = {};
      for (const [k, v] of Object.entries(patch)) {
        if (COMPANY_PATCH_KEYS.has(k)) effectivePatch[k] = v;
      }
      if (Object.keys(effectivePatch).length === 0) {
        return res.status(403).json({
          error: 'Giám đốc chỉ được sửa: company_name, company_address, company_phone.',
        });
      }
    } else if (role !== 'ADMIN') {
      return res.status(403).json({ error: 'Chỉ ADMIN hoặc Giám đốc được sửa cấu hình.' });
    }

    try {
      const cur = await pool.query(`SELECT workshop_defaults FROM app_settings WHERE id = 1`);
      const prev =
        cur.rows[0]?.workshop_defaults && typeof cur.rows[0].workshop_defaults === 'object'
          ? cur.rows[0].workshop_defaults
          : {};
      const next = deepMergeWorkshop(prev, effectivePatch);
      await pool.query(`UPDATE app_settings SET workshop_defaults = $1::jsonb, updated_at = NOW() WHERE id = 1`, [
        JSON.stringify(next),
      ]);
      res.json({ workshop_defaults: next });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  /** Upload ảnh banner QC màn KH (ADMIN). */
  r.post('/kh-ads/upload-image', auth, uploadKhAdImage.single('image'), (req, res) => {
    if (normRole(req.user.role) !== 'ADMIN') {
      return res.status(403).json({ error: 'Chỉ ADMIN được upload banner.' });
    }
    if (!req.file?.filename) {
      return res.status(400).json({ error: 'Thiếu file ảnh (field: image)' });
    }
    const imageUrl = `/uploads/kh_ads/${req.file.filename}`;
    res.status(201).json({ image_url: imageUrl, filename: req.file.filename });
  });

  return r;
}

export { khAdsUploadDir };
