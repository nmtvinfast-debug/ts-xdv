# V33 – RBAC permission audit tool

## 1) API (director/admin)
Base: `/api/rbac` (permission: `DASHBOARD`)

- `GET /roles`
  - list role -> permissions + count
- `GET /permissions`
  - list constants permissions
- `GET /validate`
  - check duplicates + unknown permission references

## 2) CLI (CI)
- `npm run rbac:audit`
- Nếu phát hiện role reference permission không tồn tại => exit code 2 (fail CI).
