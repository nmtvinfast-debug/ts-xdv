/**
 * Ghi cấu hình app_release V2 vào app_settings (để app V1 hiện dialog cập nhật).
 * Chạy: cd ts-server && node scripts/set-app-release-v2.mjs
 * Cần DATABASE_URL (hoặc fly proxy postgres).
 */
import 'dotenv/config';
import { createPool } from '../src/db/pool.js';
import { mergeWorkshopDefaults } from '../src/lib/kh_ads_config.js';
import { DEFAULT_APP_RELEASE } from '../src/lib/app_release.js';

const V2_RELEASE = {
  ...DEFAULT_APP_RELEASE,
  version_label: 'V2.0',
  version: '2.0.0',
  build_number: 200,
  message:
    'Bản V2: sửa Gọi CVDV cho khách hàng, đồng bộ dữ liệu xưởng. Vui lòng cập nhật.',
  download_url_web: 'https://ts-server.fly.dev/releases/web/',
  download_url_windows: 'https://ts-server.fly.dev/releases/ts_xdv.exe',
  download_url_android: 'https://ts-server.fly.dev/releases/ts-xdv.apk',
  download_url_ios: '',
  mandatory: false,
};

const pool = createPool();

async function main() {
  const cur = await pool.query(`SELECT workshop_defaults FROM app_settings WHERE id = 1`);
  const stored =
    cur.rows[0]?.workshop_defaults && typeof cur.rows[0].workshop_defaults === 'object'
      ? cur.rows[0].workshop_defaults
      : {};
  const merged = mergeWorkshopDefaults(stored);
  merged.app_release = { ...merged.app_release, ...V2_RELEASE };
  await pool.query(
    `UPDATE app_settings SET workshop_defaults = $1::jsonb, updated_at = NOW() WHERE id = 1`,
    [JSON.stringify(merged)],
  );
  console.log('✅ Đã cập nhật app_release V2 trên máy chủ:');
  console.log(JSON.stringify(merged.app_release, null, 2));
  await pool.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
