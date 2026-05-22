import express from 'express';
import { mergeWorkshopDefaults } from '../lib/kh_ads_config.js';
import {
  isUpdateAvailable,
  mergeAppRelease,
  pickDownloadUrl,
} from '../lib/app_release.js';

export function createAppReleaseRouter(pool) {
  const r = express.Router();

  /** GET /api/v1/app/release?version=1.0.0&build=1&platform=windows */
  r.get('/release', async (req, res) => {
    try {
      const result = await pool.query(`SELECT workshop_defaults FROM app_settings WHERE id = 1`);
      const stored = result.rows[0]?.workshop_defaults;
      const merged = mergeWorkshopDefaults(typeof stored === 'object' && stored ? stored : {});
      const release = mergeAppRelease(merged.app_release);

      const clientVersion = String(req.query.version ?? '0.0.0').trim();
      const clientBuild = parseInt(req.query.build, 10) || 0;
      const platform = String(req.query.platform ?? '').trim();

      const updateAvailable = isUpdateAvailable(clientVersion, clientBuild, release);
      const downloadUrl = pickDownloadUrl(release, platform);

      res.json({
        update_available: updateAvailable,
        version_label: release.version_label,
        latest_version: release.version,
        latest_build: release.build_number,
        message:
          String(release.message || '').trim() ||
          `Đã có phiên bản mới ${release.version_label}! Bạn có muốn cập nhật không?`,
        download_url: downloadUrl,
        mandatory: release.mandatory,
      });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  return r;
}
