import fs from 'fs';
import path from 'path';
import cron from 'node-cron';
import { config } from '../config.js';

export function registerImageRetentionCron(pool) {
  const days = config.imageRetentionDays;

  cron.schedule(process.env.MEDIA_RETENTION_CRON || '0 2 * * *', async () => {
    console.log(`[CRON] Dọn ảnh RO sau ${days} ngày ra xưởng...`);
    try {
      const query = `
        SELECT id, images FROM repair_orders
        WHERE time_out IS NOT NULL
        AND time_out < NOW() - ($1::int * INTERVAL '1 day')
        AND jsonb_array_length(COALESCE(images, '[]'::jsonb)) > 0
      `;
      const result = await pool.query(query, [days]);
      for (const order of result.rows) {
        const imagePaths = order.images || [];
        for (const imgPath of imagePaths) {
          if (typeof imgPath === 'string' && !imgPath.startsWith('data:image')) {
            const absolutePath = path.resolve(imgPath);
            fs.unlink(absolutePath, (err) => {
              if (err && err.code !== 'ENOENT') console.error(`[CRON] unlink ${imgPath}`, err);
            });
          }
        }
        await pool.query(`UPDATE repair_orders SET images = '[]'::jsonb WHERE id = $1`, [order.id]);
        console.log(`[CRON] Đã xóa ảnh DB RO ${order.id}`);
      }
      if (result.rows.length === 0) console.log('[CRON] Không có RO cần dọn ảnh.');
    } catch (e) {
      console.error('[CRON] image retention:', e);
    }
  });
}
