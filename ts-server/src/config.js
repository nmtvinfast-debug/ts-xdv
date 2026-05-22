/**
 * Cấu hình runtime — ưu tiên biến môi trường (Fly / Docker / local).
 */
export const config = {
  port: Number(process.env.PORT || 3000),
  nodeEnv: process.env.NODE_ENV || 'development',
  databaseUrl: process.env.DATABASE_URL || '',
  pgSsl: process.env.PGSSLMODE === 'require' || /\bsslmode=require\b/i.test(process.env.DATABASE_URL || ''),
  bodyLimitMb: Number(process.env.BODY_LIMIT_MB || 50),
  imageRetentionDays: Number(process.env.IMAGE_RETENTION_DAYS || 10),
  /** Giống bản `.env` cũ (JWT_SECRET=…); modular hiện dùng token `auth_token_<uuid>`, biến này dự phòng bước JWT sau. */
  jwtSecret: process.env.JWT_SECRET || '',
  /**
   * Tương thích `AUTO_MIGRATE` bản server monolithic: `0` / `false` / `off` = không gọi initSchema khi start.
   * Mặc định bật (khuyến nghị) để tự tạo/cập nhật bảng giống `initDatabase()` cũ.
   */
  autoMigrate: !/^0|false|off$/i.test(String(process.env.AUTO_MIGRATE ?? '1').trim()),
  bootstrapAdminUsername: process.env.BOOTSTRAP_ADMIN_USERNAME || '',
  bootstrapAdminPassword: process.env.BOOTSTRAP_ADMIN_PASSWORD || '',
  bootstrapAdminFullname: process.env.BOOTSTRAP_ADMIN_FULLNAME || 'Quản trị viên Tổng',
};
