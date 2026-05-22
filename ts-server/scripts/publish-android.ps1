# Build APK V2+ và copy vào ts-server/releases/ts-xdv.apk (sau đó fly deploy)
$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$app = Join-Path $root "TS-appV1"
$apkSrc = Join-Path $app "build\app\outputs\flutter-apk\app-release.apk"
$apkDst = Join-Path $root "ts-server\releases\ts-xdv.apk"

Write-Host "Build Android release..."
Push-Location $app
flutter pub get
flutter build apk --release
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }
Pop-Location

if (-not (Test-Path $apkSrc)) {
    Write-Error "Không thấy APK: $apkSrc"
}
New-Item -ItemType Directory -Force -Path (Split-Path $apkDst -Parent) | Out-Null
Copy-Item -Force $apkSrc $apkDst
$mb = [math]::Round((Get-Item $apkDst).Length / 1MB, 1)
Write-Host "OK: $apkDst ($mb MB)"
Write-Host ""
Write-Host "Cập nhật cấu hình V2 trên DB (nếu máy chủ đang báo V1):"
Write-Host "  cd ts-server"
Write-Host "  node scripts/set-app-release-v2.mjs"
Write-Host ""
Write-Host "Deploy:"
Write-Host "  cd ts-server"
Write-Host "  fly deploy"
