/**
 * Smoke workflow runner (yêu cầu server đang chạy và đã seed demo).
 * Usage:
 *   BASE_URL=http://localhost:3000 node scripts/smoke_workflow.js
 */
import dotenv from 'dotenv';
dotenv.config();

const BASE_URL = (process.env.BASE_URL || 'http://localhost:3000').replace(/\/$/, '');

async function post(path, body, token=null, idemKey=null) {
  const headers = { 'content-type': 'application/json' };
  if (token) headers['authorization'] = `Bearer ${token}`;
  if (idemKey) headers['idempotency-key'] = idemKey;
  const r = await fetch(BASE_URL + path, { method:'POST', headers, body: JSON.stringify(body||{}) });
  const t = await r.text();
  let j=null; try { j=JSON.parse(t); } catch (_e) {}
  if (!r.ok) throw new Error(`HTTP ${r.status} ${path}: ${t}`);
  return j;
}
async function get(path, token=null) {
  const headers = {};
  if (token) headers['authorization'] = `Bearer ${token}`;
  const r = await fetch(BASE_URL + path, { method:'GET', headers });
  const t = await r.text();
  let j=null; try { j=JSON.parse(t); } catch (_e) {}
  if (!r.ok) throw new Error(`HTTP ${r.status} ${path}: ${t}`);
  return j;
}

async function login(username, password) {
  const out = await post('/api/auth/login', { username, password });
  return out?.accessToken || out?.token || out?.access_token || null;
}

async function run() {
  const pass = process.env.DEMO_PASSWORD || 'Demo@123456';
  const token = await login('ketoan_demo', pass);
  if (!token) throw new Error('Login failed (no token).');

  const roId = process.env.SMOKE_RO_ID; // nếu muốn test RO cụ thể
  if (!roId) {
    console.log('[smoke] Set SMOKE_RO_ID=<uuid> để chạy đủ luồng finalize/invoice/receipt/refund.');
    console.log('[smoke] Gợi ý: chạy seed:demo sẽ in ra RO id.');
    return;
  }

  // 1) finalize
  console.log('[smoke] finalize settlement...');
  await post(`/api/settlements/${roId}`, { customer_pay: 1000000, insurance_pay: 0, debt_amount: 0 }, token, 'idem-finalize-1');

  // 2) issue invoice + receipt
  console.log('[smoke] issue invoice...');
  await post(`/api/settlements/${roId}/invoice`, {}, token, 'idem-invoice-1');
  console.log('[smoke] issue receipt...');
  await post(`/api/settlements/${roId}/receipt`, {}, token, 'idem-receipt-1');

  // 3) refund -> payment voucher
  console.log('[smoke] refund...');
  await post(`/api/settlements/${roId}/refund`, { amount: 50000, method:'cash', receiver_name:'Nguyễn Văn Demo', reason:'Test hoàn tiền' }, token, 'idem-refund-1');

  // 4) reports daily
  console.log('[smoke] reports daily...');
  const today = new Date().toISOString().slice(0,10);
  const rep = await get(`/api/reports/accounting/daily?date=${today}`, token);
  console.log('[smoke] daily summary:', JSON.stringify(rep?.settlement_summary || rep, null, 2));

  console.log('[smoke] DONE');
}

run().catch((e) => {
  console.error('[smoke] FAILED:', e.message);
  process.exit(1);
});
