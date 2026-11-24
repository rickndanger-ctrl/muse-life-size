#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
app_dir="$PWD/Muse Fullscreen.app"
# Screen Recording approval is tied to a stable signing identity. Never fall
# back to ad-hoc signing: its cdhash requirement invalidates approval on rebuild.
signing_identity="${MUSE_CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/"Apple Development:/{print $2; exit}')}"
if [[ -z "$signing_identity" ]]; then
  print -u2 'An Apple Development signing identity is required. Set MUSE_CODESIGN_IDENTITY to a stable installed identity.'
  exit 1
fi
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx15.2 \
  -framework AppKit -framework ScreenCaptureKit -framework AVFoundation \
  Sources/main.swift Sources/MuseControls.swift -o "$app_dir/Contents/MacOS/MuseFullscreen"
cp Info.plist "$app_dir/Contents/Info.plist"
codesign --force --sign "$signing_identity" --timestamp=none "$app_dir"
codesign --verify --strict "$app_dir"
