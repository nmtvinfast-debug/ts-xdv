# Phase 9R - Ops Dashboard Realtime (SSE)

## Snapshot (JSON)
- GET /api/v1/system/ops/snapshot?workshop_id=

## Stream realtime (SSE)
- GET /api/v1/system/ops/stream?workshop_id=&interval_ms=3000

Client web ví dụ:
```js
const es = new EventSource('/api/v1/system/ops/stream?interval_ms=3000');
es.addEventListener('snapshot', (e)=>{
  const data = JSON.parse(e.data);
  console.log(data);
});
```
