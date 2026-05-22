/**
 * Simple healthcheck script (optional)
 * Usage: node scripts/healthcheck.js https://yourapp.fly.dev/health
 */
import https from 'https';
import http from 'http';
import { URL } from 'url';

const target = process.argv[2] || 'http://127.0.0.1:8080/health';
const u = new URL(target);
const lib = (u.protocol === 'https:') ? https : http;

const req = lib.request(u, { method: 'GET', timeout: 5000 }, (res) => {
  let data='';
  res.on('data', (c)=>data+=c);
  res.on('end', ()=>{
    if (res.statusCode >= 200 && res.statusCode < 300) {
      // eslint-disable-next-line no-console
      console.log('OK', data.slice(0,200));
      process.exit(0);
    }
    // eslint-disable-next-line no-console
    console.error('FAIL', res.statusCode, data.slice(0,200));
    process.exit(2);
  });
});
req.on('timeout', ()=>{ req.destroy(new Error('timeout')); });
req.on('error', (e)=>{
  // eslint-disable-next-line no-console
  console.error('ERROR', e.message);
  process.exit(2);
});
req.end();
