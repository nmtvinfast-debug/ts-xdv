# Build iOS bằng GitHub (không cần Mac)

## Bước 1: Tạo repository trên GitHub

1. Đăng nhập https://github.com
2. **New repository** → tên ví dụ: `ts-xdv`
3. **Private** hoặc Public (tùy bạn)
4. **Không** tick "Add README" (repo trống)
5. Copy URL, ví dụ: `https://github.com/TENBAN/ts-xdv.git`

## Bước 2: Đẩy code từ Windows

Mở **PowerShell** trong thư mục `New folder` (thư mục chứa `TS-appV1` và `ts-server`):

```powershell
cd "C:\Users\ADMIN\Downloads\New folder"
```

**Nếu báo lỗi «running scripts is disabled»**, dùng một trong hai cách:

```cmd
scripts\setup-github-ios.bat https://github.com/nmtvinfast-debug/ts-xdv.git
```

hoặc:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup-github-ios.ps1 -RepoUrl "https://github.com/nmtvinfast-debug/ts-xdv.git"
```

Lần đầu Git hỏi đăng nhập GitHub — dùng **Personal Access Token** (Settings → Developer settings → Tokens) làm mật khẩu.

## Bước 3: Chạy build iOS trên GitHub

1. Vào repo → tab **Actions**
2. Trái chọn workflow **Build iOS**
3. **Run workflow** → nhánh `main` → **Run workflow**
4. Đợi job xanh (~15–25 phút)

## Bước 4: Tải file .ipa

1. Mở run vừa xong
2. Cuối trang → **Artifacts** → **ts-xdv-ios-ipa**
3. Giải nén → có file `.ipa`

## Giới hạn quan trọng

| Việc | GitHub Actions (--no-codesign) |
|------|-------------------------------|
| Kiểm tra app build được trên iOS | Có |
| Cài thẳng lên iPhone bằng file tải về | **Không** (Apple bắt buộc ký app) |
| Cài cho nhân viên (TestFlight / App Store) | Cần **Apple Developer 99 USD/năm** + Mac để upload |

**Cách dùng ngay không cần iOS native:** bản Web  
https://ts-server.fly.dev/releases/web/

## Tự động build khi push code

Mỗi lần `git push` lên nhánh `main` (có sửa trong `TS-appV1/`), workflow có thể chạy lại (đã bật trong file workflow).

## Lỗi thường gặp

- **Push bị từ chối:** tạo repo trống trước, hoặc `git pull origin main --rebase` rồi push lại
- **Workflow đỏ — pod:** mở log bước "CocoaPods install", thử push lại
- **Không thấy Actions:** file phải có `.github/workflows/build-ios.yml` trên nhánh `main`
