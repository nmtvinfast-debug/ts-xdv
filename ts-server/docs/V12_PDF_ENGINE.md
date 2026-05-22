# V12 – PDF Engine (RO / Báo giá / Hóa đơn)

## Endpoint
- `POST /api/pdf/ro/:roId`
- `POST /api/pdf/quote/:roId`
- `POST /api/pdf/invoice/:roId`

Trả về:
- `mediaId`
- `url` (tải có auth): `/api/media/:id`
- `signedUrlEndpoint`: `/api/media/:id/signed`

## Template Engine
- Kênh template: `PDF_HTML`
- event_code:
  - `RO_PDF`
  - `QUOTE_PDF`
  - `INVOICE_PDF`
- Migration seed:
  - `src/db/migrations/20260225103000_seed_pdf_html_templates.sql`

## Engine
- Dùng `puppeteer-core`
- Cần cấu hình Chrome/Chromium trong môi trường deploy:
  - `PUPPETEER_EXECUTABLE_PATH`
  - `PUPPETEER_ARGS`

## Storage
- Lưu PDF qua Storage Adapter v11 (local hoặc s3/r2)
- Tự insert `media_files` với kind tương ứng.
