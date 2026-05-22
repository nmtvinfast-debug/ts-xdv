import { createPool } from './db/pool.js';
import { initSchema } from './db/initSchema.js';
import { createApp } from './app.js';
import { config } from './config.js';
import { registerImageRetentionCron } from './cron/imageRetention.js';
import { registerKtvDiagnosisEscalationCron } from './cron/ktvDiagnosisEscalation.js';

export async function start() {
  const pool = createPool();
  const app = createApp(pool);
  app.locals.dbReady = null;

  if (process.env.FLY_APP_NAME && !config.databaseUrl && !process.env.PGHOST) {
    console.error(
      '[ts-server] Trên Fly cần DATABASE_URL (ví dụ: fly postgres attach …). Thiếu DB URL có thể làm initSchema lỗi.',
    );
  }

  registerImageRetentionCron(pool);
  registerKtvDiagnosisEscalationCron(pool);

  try {
    if (config.autoMigrate) {
      await initSchema(pool);
      app.locals.dbReady = true;
      console.log('✅ initSchema completed');
    } else {
      console.warn('[ts-server] AUTO_MIGRATE tắt — bỏ qua initSchema (giả định DB đã có schema).');
      app.locals.dbReady = true;
    }
  } catch (e) {
    app.locals.dbReady = false;
    console.error('❌ initSchema failed — kiểm tra DATABASE_URL / SSL / quyền DB:');
    console.error(e?.stack || e?.message || e);
  }

  const port = config.port;
  await new Promise((resolve, reject) => {
    const server = app.listen(port, '0.0.0.0', () => resolve());
    server.on('error', reject);
  });
  console.log(`TS-XDV server listening on :${port}`);

  return { app, pool };
}
