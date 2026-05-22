#!/usr/bin/env node
import pg from 'pg';
const { Pool } = pg;

function pick(obj, keys){
  const o = {};
  for(const k of keys) o[k]=obj[k];
  return o;
}

async function main(){
  const pool = new Pool({ connectionString: process.env.DATABASE_URL, max: 1 });
  const out = { ok:true, at: new Date().toISOString() };

  try{
    const r = await pool.query(`SELECT 1 FROM pg_extension WHERE extname='pg_stat_statements'`);
    out.pg_stat_statements_enabled = r.rowCount > 0;

    if(out.pg_stat_statements_enabled){
      const top = await pool.query(`
        SELECT queryid, calls, total_exec_time, mean_exec_time, rows
        FROM pg_stat_statements
        ORDER BY total_exec_time DESC
        LIMIT 20
      `);
      out.top = top.rows.map(x=>pick(x, ['queryid','calls','total_exec_time','mean_exec_time','rows']));
    } else {
      out.top = [];
      out.hint = 'Bật extension pg_stat_statements để xem top slow queries.';
    }

    const idx = await pool.query(`
      SELECT schemaname, relname as table_name, indexrelname as index_name, idx_scan, idx_tup_read, idx_tup_fetch
      FROM pg_stat_user_indexes
      ORDER BY idx_scan ASC
      LIMIT 50
    `);
    out.low_scan_indexes = idx.rows;
  }catch(e){
    out.ok=false;
    out.error = { message: e.message, code: e.code };
  }finally{
    await pool.end();
  }

  console.log(JSON.stringify(out, null, 2));
  process.exit(out.ok ? 0 : 1);
}

main();
