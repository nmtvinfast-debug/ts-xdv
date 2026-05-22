import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: __ENV.VUS ? parseInt(__ENV.VUS,10) : 10,
  duration: __ENV.DURATION || '30s',
  thresholds: {
    http_req_failed: ['rate<0.02'],
    http_req_duration: ['p(95)<1200'],
  },
};

const BASE = __ENV.BASE_URL || 'http://localhost:8080';
const TOKEN = __ENV.JWT || '';
const WORKSHOP = __ENV.WORKSHOP_ID || '';

function headers(){
  const h = { 'content-type': 'application/json' };
  if(TOKEN) h['authorization'] = `Bearer ${TOKEN}`;
  if(WORKSHOP) h['x-workshop-id'] = WORKSHOP;
  return h;
}

export default function(){
  const r1 = http.get(`${BASE}/api/v1/health`, { headers: headers() });
  check(r1, { 'health 200': (r)=> r.status===200 });

  sleep(1);
}
