#!/usr/bin/env node
import fs from 'fs';
import path from 'path';

const checks = [
  { key:'NODE_ENV', required:false },
  { key:'DATABASE_URL', required:true },
  { key:'JWT_SECRET', required:true },
  { key:'OPS_TOKEN', required:true },
  { key:'REDIS_URL', required:false },
];

const env = process.env;
const out = { ok:true, at: new Date().toISOString(), checks:[] };

for(const c of checks){
  const v = env[c.key];
  const ok = c.required ? !!v : true;
  out.checks.push({ key:c.key, required:c.required, ok: ok, present: !!v });
  if(c.required && !v) out.ok=false;
}

const root = process.cwd();
const openapi = path.join(root,'docs','openapi.json');
out.artifacts = {
  openapi_exists: fs.existsSync(openapi),
  docker_quickstart_exists: fs.existsSync(path.join(root,'docs','DOCKER_QUICKSTART.md')),
};

console.log(JSON.stringify(out, null, 2));
process.exit(out.ok ? 0 : 1);
