#!/usr/bin/env bash
# Build IPA TS-XDV trên macOS (không chạy được trên Windows).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> flutter pub get"
flutter pub get

if [[ -d ios ]] && command -v pod >/dev/null 2>&1; then
  echo "==> pod install (ios)"
  (cd ios && pod install)
fi

SIGN_ARGS=()
if [[ "${1:-}" == "--no-codesign" ]]; then
  SIGN_ARGS=(--no-codesign)
  echo "==> build ipa (không ký — chỉ kiểm tra compile)"
else
  echo "==> build ipa (cần Xcode Signing / Apple Developer)"
fi

flutter build ipa --release "${SIGN_ARGS[@]}"

echo ""
echo "Xong. Kiểm tra:"
echo "  $ROOT/build/ios/ipa/"
ls -la "$ROOT/build/ios/ipa/" 2>/dev/null || true
