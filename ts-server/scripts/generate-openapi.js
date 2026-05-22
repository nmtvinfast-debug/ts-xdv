/**
 * Phase 9B - Generate OpenAPI JSON (tối giản, tập trung endpoint chính)
 * Output: docs/openapi.json
 */
import fs from 'fs';
import path from 'path';

const spec = {
  openapi: '3.0.3',
  info: {
    title: 'TS-Server API',
    version: process.env.npm_package_version || '0.0.0',
    description: 'TS-Server (TS-XDV) API - tài liệu tối giản cho triển khai/bán thị trường.'
  },
  servers: [{ url: 'https://YOUR_DOMAIN' }],
  components: {
    securitySchemes: {
      bearerAuth: { type: 'http', scheme: 'bearer', bearerFormat: 'JWT' }
    }
  },
  security: [{ bearerAuth: [] }],
  paths: {
    '/health': { get: { summary: 'Healthcheck', security: [], responses: { '200': { description: 'OK' } } } },
    '/metrics': { get: { summary: 'Prometheus metrics', security: [], responses: { '200': { description: 'Metrics' } } } },

    '/api/v1/auth/login': { post: { summary: 'Đăng nhập', responses: { '200': { description: 'OK' } } } },

    '/api/v1/org/consolidated/dashboard': { get: { summary: 'Dashboard hợp nhất', responses: { '200': { description: 'OK' } } } },
    '/api/v1/org/consolidated/finance': { get: { summary: 'Tài chính hợp nhất', responses: { '200': { description: 'OK' } } } },
    '/api/v1/org/consolidated/finance.xlsx': { get: { summary: 'Export tài chính hợp nhất', responses: { '200': { description: 'XLSX' } } } },
    '/api/v1/org/consolidated/ranking/workshops': { get: { summary: 'Ranking XDV', responses: { '200': { description: 'OK' } } } },
    '/api/v1/org/consolidated/ranking/branches': { get: { summary: 'Ranking chi nhánh', responses: { '200': { description: 'OK' } } } },
    '/api/v1/org/consolidated/ros': { get: { summary: 'Drill-down RO', responses: { '200': { description: 'OK' } } } },

    '/api/v1/hr/attendance': { get: { summary: 'Chấm công', responses: { '200': { description: 'OK' } } } },
    '/api/v1/payroll/runs/generate': { post: { summary: 'Generate payroll run', responses: { '200': { description: 'OK' } } } },

    '/api/v1/debug/diag': { get: { summary: 'Chẩn đoán server', responses: { '200': { description: 'OK' } } } },
  }
};

const out = path.join(process.cwd(), 'docs', 'openapi.json');
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, JSON.stringify(spec, null, 2), 'utf-8');
// eslint-disable-next-line no-console
console.log('Wrote', out);
