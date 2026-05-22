# V10 – Upload + Media logging (retention 10 ngày)

## Endpoint
- `POST /api/media/upload` (form-data)
  - file (required)
  - kind (CHECKIN_PHOTO | RO_ATTACHMENT | ...)
  - carId (optional)
  - roId (optional)
- `GET /api/media/:id`
- `DELETE /api/media/:id`

## Quyền (RBAC)
- media:read
- media:write

## Retention
- Job v7 dọn theo bảng `media_files`:
  - `IMAGE_RETENTION_DAYS=10` (mặc định)
  - `npm run worker:retention`

## Lưu ý triển khai
- UPLOADS_DIR mặc định: `uploads/`
- File path lưu **tương đối**: `<workshopId>/<kind>/<filename>` để dễ move storage sau này (S3/R2).
