# V29 – Rate limit + Validation + Security hardening

## 1) Rate limit
Đã có Redis rate limiter `src/infra/ratelimit.js` (bật bằng ENV):
- `RATE_LIMIT_ENABLED=1`
- `RATE_LIMIT_WINDOW_SEC=60`
- `RATE_LIMIT_MAX_PER_WINDOW=600`

Bucket theo: workshop/company + user + ip + route + window.

## 2) Validation
Middleware mới:
- `src/middleware/validate.js`

Đã áp dụng cho:
- `POST /api/auth/login` (username/password)
- `POST /api/settlements/:roId` (customer_pay/insurance_pay/debt_amount)
- `POST /api/settlements/:roId/refund` (amount/method/receiver_name/reason)
- `POST /api/debts/:id/pay` (amount/method/note)
- `POST /api/debts/:id/adjust` (delta/reason)

Trả lỗi:
- HTTP 400 `{ ok:false, message:'Dữ liệu không hợp lệ.', errors:[...] }`

## 3) Security headers + body size limit
- Helmet đã cấu hình `contentSecurityPolicy: false` (tránh lỗi với hệ thống API).
- Header bổ sung: `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`
- JSON body limit theo ENV:
  - `BODY_LIMIT_MB=10`
