#!/bin/bash
# 构建 氛围音播放器.app（纯 swiftc，无需 Xcode 工程）
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="氛围音播放器"
EXE_NAME="ambient-mixer"
BUILD_DIR="../build"
APP="$BUILD_DIR/$APP_NAME.app"

export PATH="/Library/Developer/CommandLineTools/usr/bin:$PATH"

rm -rf "$BUILD_DIR"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ../web/player.html "$APP/Contents/Resources/player.html"
cp Info.plist "$APP/Contents/Info.plist"

ICONSET="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Assets/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -z "$retina_size" "$retina_size" Assets/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

xcrun --sdk macosx swiftc -O -swift-version 5 \
  -o "$APP/Contents/MacOS/$EXE_NAME" \
  main.swift \
  -framework AppKit -framework WebKit

codesign --force -s - "$APP"
codesign --verify --verbose=1 "$APP"

echo "BUILD OK: $APP"
