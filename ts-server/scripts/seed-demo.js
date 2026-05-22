/**
 * Phase 9B - Seed demo data (tối giản) để chạy thử nhanh
 * Chạy: npm run seed
 * Yêu cầu: DATABASE_URL đã set và migrations đã chạy.
 */
import { query } from '../src/db/pool.js';
import { uuidv4 } from '../src/utils/uuid.js';

async function main() {
  const companyId = uuidv4();
  const regionId = uuidv4();

  await query(`INSERT INTO org_companies(id, code, name, is_active) VALUES($1,'DEMO','Công ty Demo',true) ON CONFLICT DO NOTHING`, [companyId]);
  await query(`INSERT INTO org_regions(id, company_id, code, name, is_active) VALUES($1,$2,'MB','Miền Bắc',true) ON CONFLICT DO NOTHING`, [regionId, companyId]);

  // pick first workshop/branch if exists; otherwise create only if schema supports
  const ws = await query(`SELECT id FROM workshops ORDER BY created_at ASC LIMIT 1`);
  if (ws.rowCount) {
    await query(`UPDATE workshops SET company_id=$2, region_id=$3 WHERE id=$1`, [ws.rows[0].id, companyId, regionId]);
  }

  // seed done
  // eslint-disable-next-line no-console
  console.log('Seed done: company=', companyId, 'region=', regionId);
  process.exit(0);
}

main().catch((e)=>{
  // eslint-disable-next-line no-console
  console.error(e);
  process.exit(1);
});
