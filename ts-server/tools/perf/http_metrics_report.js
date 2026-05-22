#!/usr/bin/env node
const base = process.env.BASE_URL || 'http://localhost:8080';
console.log('CÁCH LẤY HTTP METRICS:');
console.log(`curl -H "x-ops-token: $OPS_TOKEN" ${base}/api/v1/ops/perf/http-metrics`);
console.log('RESET HTTP METRICS:');
console.log(`curl -X POST -H "x-ops-token: $OPS_TOKEN" ${base}/api/v1/ops/perf/http-metrics/reset`);
console.log('GỢI Ý INDEX:');
console.log(`curl -H "x-ops-token: $OPS_TOKEN" ${base}/api/v1/ops/perf/index-suggestions`);
