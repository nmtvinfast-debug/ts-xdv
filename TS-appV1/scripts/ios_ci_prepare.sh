#!/usr/bin/env bash
# Trên GitHub Actions (macOS): tạo lại scaffold iOS + giữ Info.plist, icon, Podfile tùy chỉnh.
set -euo pipefail
cd "$(dirname "$0")/.."
BK="$(mktemp -d)"
echo "Backup iOS custom files → $BK"
cp ios/Runner/Info.plist "$BK/"
cp -r ios/Runner/Assets.xcassets/AppIcon.appiconset "$BK/"
cp scripts/ios_Podfile.template "$BK/Podfile"

echo "flutter create --platforms=ios --overwrite"
flutter create . --platforms=ios --overwrite

cp "$BK/Info.plist" ios/Runner/Info.plist
cp -r "$BK/AppIcon.appiconset/"* ios/Runner/Assets.xcassets/AppIcon.appiconset/
cp "$BK/Podfile" ios/Podfile

node scripts/generate_ios_icons.mjs
echo "iOS CI prepare done."
