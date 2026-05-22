# TS Backend Admin API Pack

Gói này bổ sung **Admin tổng tạo XDV + Giám đốc** theo đúng docs `API.md`:

- `GET /api/v1/admin/workshops?q=`
- `POST /api/v1/admin/workshops`
- `PATCH /api/v1/admin/workshops/:id`
- `POST /api/v1/admin/workshops/:id/reset_director_password`
- `GET /api/v1/users`
- `POST /api/v1/users`
- `PUT /api/v1/users/:id`

## Vì sao tôi làm gói rời?
File `ts-server.zip` bạn gửi **không có source backend đang chạy** để patch trực tiếp.
Nó có docs + node_modules, nhưng **không có package.json/app source** rõ ràng để gắn route vào app hiện tại.

Vì vậy tôi làm thành **drop-in pack** để bạn hoặc dev backend:
1. chạy SQL migration
2. chép route/service vào source backend thật
3. mount router vào app Express/Fastify đang chạy

## Bước 1 - SQL
Chạy file:
- `sql/001_admin_workshops_pack.sql`

## Bước 2 - package
Cần các package:
- `pg`
- `bcryptjs`
- `express`

## Bước 3 - mount route
Ví dụ trong Express app:
```js
const adminWorkshopsRouter = require('./src/routes/admin_workshops.router');
const usersRouter = require('./src/routes/users.router');

app.use('/api/v1/admin/workshops', adminWorkshopsRouter);
app.use('/api/v1/users', usersRouter);
```

## Bước 4 - middleware auth
Router giả định request đã có:
```js
req.user = {
  id: '...',
  role: 'admin_global' // hoặc admin_tong
}
```

Nếu app bạn đang dùng middleware auth khác, chỉ cần map `req.user`.

## Kiểm thử nhanh
Xem file:
- `docs/curl_test_examples.md`
