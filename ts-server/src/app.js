import express from 'express';
import cors from 'cors';
import morgan from 'morgan';
import helmet from 'helmet';
import path from 'path';
import { fileURLToPath } from 'url';
import { config } from './config.js';
import { createAuthRouter } from './routes/auth.routes.js';
import { createUsersRouter } from './routes/users.routes.js';
import { createXdvsRouter } from './routes/xdvs.routes.js';
import { createBookingsRouter } from './routes/bookings.routes.js';
import { createRepairOrdersRouter } from './routes/repair_orders.routes.js';
import { createDashboardRouter } from './routes/dashboard.routes.js';
import { createSettingsRouter } from './routes/settings.routes.js';
import { createNotificationsRouter } from './routes/notifications.routes.js';
import { createInventoryRouter } from './routes/inventory.routes.js';
import { createOcrRouter } from './routes/ocr.routes.js';
import { createDocumentsRouter } from './routes/documents.routes.js';
import { createExtrasRouter } from './routes/extras.routes.js';
import { createCompanyChatRouter } from './routes/company_chat.routes.js';
import { createAppReleaseRouter } from './routes/app_release.routes.js';
import { createWorkshopDataRouter } from './routes/workshop_data.routes.js';

export function createApp(pool) {
  const app = express();
  app.use(helmet({ contentSecurityPolicy: false }));
  app.use(cors());
  if (config.nodeEnv !== 'test') {
    app.use(morgan('combined'));
  }
  app.use(express.json({ limit: `${config.bodyLimitMb}mb` }));
  app.use(express.urlencoded({ limit: `${config.bodyLimitMb}mb`, extended: true }));

  const uploadsRoot = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'uploads');
  app.use('/uploads', express.static(uploadsRoot));

  const releasesRoot = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'releases');
  const webReleaseRoot = path.join(releasesRoot, 'web');
  const webIndex = path.join(webReleaseRoot, 'index.html');
  // Không redirect 301 — tránh ERR_TOO_MANY_REDIRECTS với express.static (redirect mặc định).
  app.use('/releases/web', express.static(webReleaseRoot, { index: 'index.html', redirect: false }));
  app.get(['/releases/web', '/releases/web/'], (_req, res) => {
    res.sendFile(webIndex);
  });
  app.use('/releases', express.static(releasesRoot, { redirect: false }));

  app.get('/health', (req, res) => {
    const dr = req.app.locals?.dbReady;
    if (dr !== true) {
      return res.status(503).json({
        status: dr === false ? 'degraded' : 'starting',
        service: 'ts-xdv-server',
        env: config.nodeEnv,
        db_ready: dr === false ? false : 'pending',
      });
    }
    res.json({
      status: 'ok',
      service: 'ts-xdv-server',
      env: config.nodeEnv,
      db_ready: true,
    });
  });

  app.use('/api/v1/auth', createAuthRouter(pool));
  app.use('/api/v1/users', createUsersRouter(pool));
  app.use('/api/v1/xdvs', createXdvsRouter(pool));
  app.use('/api/v1/bookings', createBookingsRouter(pool));
  app.use('/api/v1/repair-orders', createRepairOrdersRouter(pool));
  app.use('/api/v1/dashboard', createDashboardRouter(pool));
  app.use('/api/v1/settings', createSettingsRouter(pool));
  app.use('/api/v1/notifications', createNotificationsRouter(pool));
  app.use('/api/v1/inventory', createInventoryRouter(pool));
  app.use('/api/v1/ocr', createOcrRouter());
  app.use('/api/v1/documents', createDocumentsRouter(pool));
  app.use('/api/v1/extras', createExtrasRouter(pool));
  app.use('/api/v1/company-chat', createCompanyChatRouter(pool));
  app.use('/api/v1/app', createAppReleaseRouter(pool));
  app.use('/api/v1/workshop-data', createWorkshopDataRouter(pool));

  return app;
}
