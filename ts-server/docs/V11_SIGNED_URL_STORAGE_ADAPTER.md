# V11 – Signed URL + Storage Adapter (Local / S3 / R2)

## 1) Storage Adapter
- `STORAGE_MODE=local` (mặc định): lưu file vào `UPLOADS_DIR` và stream trực tiếp.
- `STORAGE_MODE=s3`: upload lên S3-compatible (AWS S3 / Cloudflare R2 / MinIO). DB lưu `file_path` là **object key**.

ENV S3/R2:
- S3_BUCKET
- S3_REGION (R2 thường để `auto`)
- S3_ENDPOINT (R2: https://<accountid>.r2.cloudflarestorage.com)
- S3_ACCESS_KEY_ID / S3_SECRET_ACCESS_KEY

## 2) Signed URL (chia sẻ không cần đăng nhập)
- API (có auth): `GET /api/media/:id/signed?ttl=300`
  - S3 mode: trả về **presigned URL**
  - Local mode: trả về link public dạng:
    - `/public/media/:id?exp=...&sig=...`

ENV local signed:
- MEDIA_SIGNING_SECRET (bắt buộc nếu dùng local signed url)

## 3) Public endpoint
- `GET /public/media/:id?exp=...&sig=...`
  - Local mode: verify HMAC rồi stream file
  - S3 mode: verify HMAC rồi redirect tới presigned URL

## 4) Retention
- Job v7 đã được nâng cấp: dọn `media_files` và gọi storage adapter delete object/file.
