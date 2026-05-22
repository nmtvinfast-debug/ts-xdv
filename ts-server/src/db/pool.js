import pkg from 'pg';
import { config } from '../config.js';

const { Pool } = pkg;

/**
 * Giống bản monolithic cũ: khi deploy Fly mà KHÔNG có DATABASE_URL / PGHOST,
 * dùng Postgres nội bộ Fly đã attach trước đây (IPv6 + user ts_server).
 * CẢNH BÁO: mật khẩu DB nằm trong source — chỉ dùng nếu bạn chấp nhận rủi ro; nên dùng secret sau này.
 */
const FLY_LEGACY_PG = {
  user: 'ts_server',
  password: 'qnJ4K4FJAGzfDj2',
  host: 'fdaa:46:b375:0:1::3',
  database: 'ts_server',
  port: 5432,
};

/** Host Postgres trên mạng riêng Fly: không dùng TLS (tránh lỗi "TLS connection" với pg). */
function isFlyPrivatePgHost(host) {
  if (!host) return false;
  const h = host.replace(/^\[(.+)\]$/u, '$1').trim();
  return h.endsWith('.internal') || h.startsWith('fdaa:');
}

/**
 * SSL cho Postgres — chỉ khi URL/env thật sự yêu cầu.
 * Không ép TLS cho host `.internal` / IPv6 `fdaa:` (Fly nội bộ thường là plaintext).
 */
function sslForConnectionString(cs) {
  if (!cs) return undefined;
  if (/sslmode=disable/i.test(cs)) return undefined;
  try {
    const normalized = cs.replace(/^postgres:/i, 'postgresql:');
    const u = new URL(normalized);
    let h = u.hostname;
    if (h.startsWith('[') && h.endsWith(']')) h = h.slice(1, -1);
    if (h === 'localhost' || h === '127.0.0.1') return undefined;
    if (isFlyPrivatePgHost(h)) {
      if (!/sslmode=require|verify-full|verify-ca/i.test(cs)) return undefined;
    }
  } catch {
    /* ignore parse errors */
  }
  if (/sslmode=require|verify-full|verify-ca/i.test(cs)) return { rejectUnauthorized: false };
  if (process.env.PGSSLMODE === 'require') return { rejectUnauthorized: false };
  if (config.pgSsl) return { rejectUnauthorized: false };
  return undefined;
}

function useFlyLegacyEmbeddedDb() {
  return (
    Boolean(process.env.FLY_APP_NAME) &&
    !config.databaseUrl?.trim() &&
    !process.env.PGHOST?.trim()
  );
}

/**
 * Pool Postgres: DATABASE_URL (ưu tiên) hoặc PG* hoặc (Fly) cấu hình legacy nhúng.
 */
export function createPool() {
  const cs = config.databaseUrl?.trim();

  if (cs) {
    const ssl = sslForConnectionString(cs);
    return new Pool({
      connectionString: cs,
      ssl,
      max: Number(process.env.PGPOOL_MAX || 20),
      connectionTimeoutMillis: Number(process.env.PG_CONNECTION_TIMEOUT_MS || 10000),
    });
  }

  if (useFlyLegacyEmbeddedDb()) {
    console.warn(
      '[ts-server] Fly: không có DATABASE_URL — dùng Postgres nhúng (monolithic). ' +
        'Nếu cluster đã đổi host: set fly secrets set DATABASE_URL=... hoặc PGHOST=...',
    );
    return new Pool({
      ...FLY_LEGACY_PG,
      /* Fly 6PN: Postgres nội bộ không bắt STARTTLS; bật ssl ở đây gây: disconnected before TLS */
      ssl: false,
      max: Number(process.env.PGPOOL_MAX || 20),
      connectionTimeoutMillis: Number(process.env.PG_CONNECTION_TIMEOUT_MS || 10000),
    });
  }

  const user = process.env.PGUSER || 'postgres';
  const password = process.env.PGPASSWORD || '';
  const host = process.env.PGHOST || '127.0.0.1';
  const port = Number(process.env.PGPORT || 5432);
  const database = process.env.PGDATABASE || 'postgres';
  const internal = host === 'localhost' || host === '127.0.0.1' || isFlyPrivatePgHost(host);
  const ssl =
    !internal && process.env.PGSSLMODE === 'require' ? { rejectUnauthorized: false } : undefined;
  return new Pool({
    user,
    password,
    host,
    port,
    database,
    ssl,
    max: Number(process.env.PGPOOL_MAX || 20),
    connectionTimeoutMillis: Number(process.env.PG_CONNECTION_TIMEOUT_MS || 10000),
  });
}
