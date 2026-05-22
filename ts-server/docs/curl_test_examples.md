## 1) Danh sách workshop
```bash
curl -H "Authorization: Bearer <ADMIN_TOKEN>"   "https://ts-server.fly.dev/api/v1/admin/workshops?q="
```

## 2) Tạo XDV + Giám đốc
```bash
curl -X POST "https://ts-server.fly.dev/api/v1/admin/workshops"   -H "Authorization: Bearer <ADMIN_TOKEN>"   -H "Content-Type: application/json"   -d '{
    "name":"XDV Hunter Mai Linh CS5",
    "code":"N64303",
    "address":"Phường Quyết Thắng, Tỉnh Thái Nguyên",
    "backend_url":"https://ts-server.fly.dev",
    "contact_phone":"0343898926",
    "contact_email":"cs5.thaithanh.html@gmail.com",
    "director_username":"giamdoc",
    "director_password":"123456",
    "director_full_name":"Giám đốc XDV"
  }'
```

## 3) Reset mật khẩu Giám đốc
```bash
curl -X POST "https://ts-server.fly.dev/api/v1/admin/workshops/<WORKSHOP_ID>/reset_director_password"   -H "Authorization: Bearer <ADMIN_TOKEN>"   -H "Content-Type: application/json"   -d '{"new_password":"123456"}'
```

## 4) Danh sách user
```bash
curl -H "Authorization: Bearer <TOKEN>"   "https://ts-server.fly.dev/api/v1/users"
```
