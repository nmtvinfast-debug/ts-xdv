# Đưa bản Flutter web lên ts-server/releases/web (sau đó fly deploy)
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$app = Join-Path $root "TS-appV1"
$server = Join-Path $root "ts-server"
$dst = Join-Path $server "releases\web"

Write-Host "Build web (base-href /releases/web/)..."
Push-Location $app
flutter build web --release --base-href "/releases/web/"
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }
Pop-Location

New-Item -ItemType Directory -Force -Path $dst | Out-Null
Write-Host "Copy -> $dst"
xcopy /E /I /Y (Join-Path $app "build\web\*") "$dst\"

Write-Host "Xong. Chay deploy:"
Write-Host "  cd ts-server"
Write-Host "  fly deploy"
