# V25 – E-invoice adapter (stub) + status tracking + retry

## DB
- `einvoices` lưu trạng thái gửi HĐĐT (pending/sent/accepted/rejected/error), attempt_count, next_retry_at
- invoices mirror: `einvoice_status`, `einvoice_provider`, `einvoice_ref`

## Provider
- Interface: `src/services/einvoice/providers/providerInterface.js`
- Stub: `src/services/einvoice/providers/stubProvider.js`

## Service
- `src/services/einvoiceService.js`
  - build payload từ invoice + RO + ro_items/parts_items
  - submit/check
  - retry processor (manual/cron)

## API
Base: `/api/einvoice`
- `POST /:roId/submit` body `{ "provider": "stub" }` (Idempotency op: EINVOICE_SUBMIT)
- `GET /:roId/status`
- `POST /retry` body `{ "limit": 50 }`

ENV:
- `EINVOICE_PROVIDER=stub`
