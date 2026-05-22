# V30 – OpenAPI/Swagger + Postman pack

## Files
- `docs/openapi.yaml` (OpenAPI 3.0)
- `docs/postman_collection_v30.json` (Postman collection)

## Endpoints phục vụ file
- `GET /api/docs/openapi.yaml`
- `GET /api/docs/postman.json`

## Cách dùng Swagger
1) Mở Swagger Editor (web) hoặc VSCode extension.
2) Import `openapi.yaml`.
3) Chọn server `/api` và test bằng Bearer token.

## Cách dùng Postman
1) Import `postman_collection_v30.json`
2) Set variables:
   - `baseUrl` (vd: http://localhost:3000/api)
   - `token` (dán accessToken)
   - `roId` (uuid RO demo)
