# V6 – Seed full template + schema

## Migration mới
- `src/db/migrations/20260225094700_seed_full_templates_and_schemas.sql`

Migration này sẽ:
- Upsert **event_schemas** cho toàn bộ event_code chuẩn workflow TS
- Seed **GLOBAL templates** cho 3 kênh: `PUSH`, `IN_APP`, `EMAIL`
- Mỗi template seed sẵn bản `version=1` và `status=PUBLISHED`

## Ghi chú
- Nếu anh muốn override theo từng xưởng: tạo definition scope=WORKSHOP rồi publish version mới.
- Template Engine runtime sẽ ưu tiên WORKSHOP → GLOBAL.
