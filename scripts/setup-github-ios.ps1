# Đẩy project lên GitHub và hướng dẫn chạy workflow Build iOS.
# Chạy trong PowerShell từ thư mục "New folder":
#   .\scripts\setup-github-ios.ps1 -RepoUrl "https://github.com/TEN_BAN/ts-xdv.git"

param(
    [Parameter(Mandatory = $true)]
    [string]$RepoUrl
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "Chưa cài Git. Tải: https://git-scm.com/download/win"
}

if (-not (Test-Path ".git")) {
    git init
    git branch -M main
}

git add -A
git status --short
$msg = "TS-XDV: Flutter app + server + GitHub iOS build workflow"
git commit -m $msg 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Không có thay đổi mới hoặc đã commit trước đó."
}

git remote remove origin 2>$null
git remote add origin $RepoUrl

Write-Host ""
Write-Host "Đang push lên GitHub (cần đăng nhập GitHub lần đầu)..."
git push -u origin main

Write-Host ""
Write-Host "=== Xong push ==="
Write-Host "1. Mở repo trên GitHub -> tab Actions"
Write-Host "2. Chọn workflow 'Build iOS' -> Run workflow -> Run workflow"
Write-Host "3. Đợi ~15-25 phút (máy Mac ảo của GitHub)"
Write-Host "4. Vào run thành công -> Artifacts -> tải 'ts-xdv-ios-ipa'"
Write-Host ""
Write-Host "Lưu ý: file .ipa --no-codesign chưa cài trực tiếp lên iPhone."
Write-Host "Để cài máy thật cần Apple Developer + ký trên Mac hoặc TestFlight."
