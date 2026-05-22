# Build app iOS (TS-XDV)

## Quan trọng: bắt buộc máy Mac

Apple **không cho** build file `.ipa` / cài lên iPhone trên **Windows**. Máy bạn đang dùng Windows nên cần một trong các cách sau:

| Cách | Cần gì |
|------|--------|
| **Mac + Xcode** | MacBook/iMac/Mac mini, Xcode (App Store), tài khoản Apple |
| **GitHub Actions** | Repo trên GitHub, workflow `build-ios.yml` (máy Mac ảo của GitHub) |
| **TestFlight (chính thức)** | Apple Developer **99 USD/năm** + Mac để upload |

Trên Windows vẫn dùng được **Web** và **Android APK** như hiện tại.

---

## Chuẩn bị trên Mac (lần đầu)

1. Cài **Xcode** từ App Store (mở Xcode một lần, chấp nhận license).
2. Cài Flutter: https://docs.flutter.dev/get-started/install/macos
3. Terminal:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
flutter doctor
```

`flutter doctor` phải có dấu ✓ cho **Xcode** và **CocoaPods** (hoặc Swift PM).

4. Copy project `TS-appV1` sang Mac (USB, Git, hoặc zip).

---

## Icon app (bắt buộc trước khi đóng gói)

Thư mục `ios/Runner/Assets.xcassets/AppIcon.appiconset/` hiện **chưa có file PNG**.

Trong **Xcode** → `Runner` → **Assets** → **AppIcon** → kéo ảnh **1024×1024** vào ô marketing, hoặc dùng https://appicon.co tạo bộ icon rồi copy vào thư mục đó.

---

## Cách 1: Chạy thử trên iPhone (cáp USB / cùng Wi‑Fi)

```bash
cd TS-appV1
flutter pub get
cd ios && pod install && cd ..   # nếu flutter báo cần CocoaPods
open ios/Runner.xcworkspace
```

Trong Xcode:

1. Chọn target **Runner** → **Signing & Capabilities** → bật **Automatically manage signing**.
2. Chọn **Team** (Apple ID cá nhân miễn phí cũng được, giới hạn 7 ngày / 3 app).
3. Đổi **Bundle Identifier** thành duy nhất, ví dụ: `com.tenban.tsxdv` (không dùng `com.example.*` khi lên máy thật).

Cắm iPhone, chọn máy trên thanh Xcode, bấm **Run** (▶).

Hoặc terminal:

```bash
flutter run -d <id-iphone>
```

---

## Cách 2: Build file `.ipa` (cài nội bộ / TestFlight)

Script có sẵn:

```bash
chmod +x scripts/build_ios.sh
./scripts/build_ios.sh
```

Hoặc thủ công:

```bash
cd TS-appV1
flutter pub get
flutter build ipa --release
# Chưa có chứng chỉ Apple Developer:
flutter build ipa --no-codesign
```

File thường nằm tại:

`build/ios/ipa/ts_xdv.ipa`

### Cài nội bộ (không lên App Store)

- Cần **Apple Developer Program** hoặc profile Ad Hoc.
- Hoặc dùng **TestFlight** (upload từ Xcode → Organizer → Distribute).

### Không có Mac — build trên GitHub

1. Push code lên GitHub.
2. Vào tab **Actions** → workflow **Build iOS** → **Run workflow**.
3. Tải artifact `.ipa` (bản `--no-codesign` chỉ để kiểm tra build, cài máy vẫn cần ký chứng chỉ).

---

## Lỗi thường gặp

| Lỗi | Xử lý |
|-----|--------|
| `No valid code signing` | Xcode → Signing → chọn Team; hoặc `flutter build ipa --no-codesign` |
| Thiếu icon | Thêm PNG vào `AppIcon.appiconset` |
| `pod install` lỗi | `cd ios && pod repo update && pod install` |
| Plugin AdMob | Đổi `GADApplicationIdentifier` trong `Info.plist` sang ID thật từ AdMob |

---

## Phân phối cho nhân viên

- **Nhanh, không cần App Store:** TestFlight (cần Developer 99 USD/năm).
- **Chỉ vài máy:** Ad Hoc IPA + UDID từng máy.
- **Không có iPhone / không có Mac:** dùng **bản Web** `https://ts-server.fly.dev/releases/web/`.
