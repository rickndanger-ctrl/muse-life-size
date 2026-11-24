#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
app_dir="$PWD/Muse Fullscreen.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx15.2 \
  -framework AppKit -framework ScreenCaptureKit -framework AVFoundation \
  Sources/main.swift -o "$app_dir/Contents/MacOS/MuseFullscreen"
cp Info.plist "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"
codesign --verify --strict "$app_dir"
