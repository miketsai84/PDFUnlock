#!/bin/bash
# 編譯並打包「PDF密碼移除.app」（Universal：Apple Silicon + Intel）
set -euo pipefail
cd "$(dirname "$0")"

APP="build/PDF密碼移除.app"
TMP="build/.tmp"

rm -rf "$APP" "$TMP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$TMP"

# 1. 產生圖示（黑底白字「密」）
swift tools/make_icon.swift "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

# 2. 編譯兩種架構後合併
for arch in arm64 x86_64; do
    swiftc -O -parse-as-library \
        -target "$arch-apple-macos13.0" \
        Sources/*.swift \
        -o "$TMP/PDFUnlock-$arch"
done
lipo -create "$TMP/PDFUnlock-arm64" "$TMP/PDFUnlock-x86_64" \
    -output "$APP/Contents/MacOS/PDFUnlock"

cp Info.plist "$APP/Contents/Info.plist"
rm -rf "$TMP"

# 3. ad-hoc 簽章（本機直接執行用）
codesign --force --sign - "$APP"

echo "✅ 已建置：$APP"
echo "   執行：open \"$APP\""
