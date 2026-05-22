# Fly local dev (Cách 2 – proxy)

Mục tiêu: chạy server ở máy bạn (Windows) nhưng DB nằm trên Fly.

## 1) Bật proxy DB

PowerShell:

```powershell
cd D:\ts-server
./scripts/fly-proxy-db.ps1 -DbApp ts-xdv-db -LocalPort 15432 -RemotePort 5432
```

> Nếu Postgres của bạn thực chạy ở port 5433 (bên trong VM), hãy dùng `-RemotePort 5433`.

## 2) Cấu hình .env

`.env` (ví dụ):

```env
PORT=3000
DATABASE_URL=postgres://postgres:<YOUR_PASSWORD>@127.0.0.1:15432/postgres?sslmode=disable
JWT_SECRET=change_me
```

## 3) Migrate + Seed + Start

```powershell
npm install
npm run migrate
npm run seed
npm start
```

## 4) Tenant header

Tất cả API nghiệp vụ (RO/Kho/Kế toán/…) dùng tenant theo header:

`x-workshop-id: <workshop_id>`

Nếu không truyền header, server sẽ **fallback** theo workshop của user trong JWT.
