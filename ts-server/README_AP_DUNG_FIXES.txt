HƯỚNG DẪN ÁP DỤNG (TS-SERVER)

1) Sửa lỗi Fly crash: SyntaxError 'Unexpected token if'
   - Copy file: src/services/workshopProfileService.js
     từ gói này -> đè vào dự án.

2) Sửa lỗi thiếu exceljs (chuyển sang dùng xlsx, không cần exceljs)
   - Copy file: src/modules/director_panel.js
     từ gói này -> đè vào dự án.

3) Sửa lỗi Deploy: npm error "Invalid Version"
   - Nguyên nhân: package-lock.json có version dạng "v1.36.3" (không hợp lệ với npm)
   - Copy file package-lock.json từ gói này -> đè vào dự án.

Sau đó chạy lại:
- Ở máy local:
  npm ci   (hoặc npm install)
- Deploy:
  flyctl deploy --app ts-server

Nếu trước đó bạn đã xóa package-lock.json thì HÃY copy lại file package-lock.json trong gói này (bắt buộc).
