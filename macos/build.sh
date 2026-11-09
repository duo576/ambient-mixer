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

xcrun --sdk macosx swiftc -O -swift-version 5 \
  -o "$APP/Contents/MacOS/$EXE_NAME" \
  main.swift \
  -framework AppKit -framework WebKit

codesign --force -s - "$APP"
codesign --verify --verbose=1 "$APP"

echo "BUILD OK: $APP"
