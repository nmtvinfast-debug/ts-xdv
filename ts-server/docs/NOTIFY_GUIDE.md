# Phase 9D - Hướng dẫn tích hợp Zalo OA / SMS / Email

## 1) Email (SMTP)
Env:
- SMTP_HOST
- SMTP_PORT
- SMTP_USER
- SMTP_PASS
- SMTP_FROM (optional)
- SMTP_SECURE=0/1

Kênh: `email`

## 2) SMS
Env:
- SMS_PROVIDER=demo|custom
- SMS_API_URL (custom)
- SMS_API_KEY (custom)

Kênh: `sms`

## 3) Zalo OA (skeleton)
Env:
- ZALO_OA_ACCESS_TOKEN
- ZALO_OA_API_BASE (default https://openapi.zalo.me)

Kênh: `zalo`
Lưu ý: API Zalo OA thực tế có nhiều loại message/template. Module hiện để khung tích hợp, khi dùng nhà cung cấp cụ thể sẽ map endpoint chuẩn.

## 4) Template
- Tạo template: `POST /api/v1/notify/templates`
- Test gửi: `POST /api/v1/notify/send-test`

Ví dụ vars gợi ý:
- customer_name
- bien_so
- appt_time
- workshop_name
- ro_code
- amount_due

## 5) Outbox
- Xem lịch sử gửi: `GET /api/v1/notify/outbox`
- Export Excel: `GET /api/v1/notify/outbox/export.xlsx`


## 6) Cảnh báo đánh giá thấp (Phase 9H)
Env:
- FEEDBACK_ALERT_CHANNEL=sms|zalo|email (mặc định sms)
- FEEDBACK_ALERT_TEMPLATE=FEEDBACK_ALERT_LOW (mặc định)
- FEEDBACK_ALERT_TO=<sđt/email/zalo_user_id nhận cảnh báo>

Tạo template code `FEEDBACK_ALERT_LOW` trong `/api/v1/notify/templates`.
Gợi ý vars:
- severity, ro_id, bien_so, customer_name, customer_phone, rating, nps, comment, feedback_link
