# Tests (V27)

Hệ thống TS-Server phụ thuộc PostgreSQL + migrations, nên test tích hợp chạy tốt nhất theo 2 cách:

## Cách 1: Smoke runner (khuyến nghị)
1) `npm run migrate`
2) `npm run seed`
3) `npm run seed:demo`
4) `npm run dev` (hoặc start)
5) Set `SMOKE_RO_ID=<id in seed:demo output>`
6) `BASE_URL=http://localhost:3000 npm run smoke`

## Cách 2: Node built-in test runner
Bạn có thể tự viết thêm test trong `tests/*.test.js` và chạy:
- `npm test`
