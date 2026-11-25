#!/bin/zsh
# Build Muse Fullscreen.app from source. Needs the Xcode command-line tools
# (xcode-select --install). Apple Silicon, macOS 15.2 or later.
set -euo pipefail
cd "${0:A:h}"
app_dir="$PWD/Muse Fullscreen.app"
# macOS ties the Screen Recording and Accessibility approvals to the signature.
# A stable certificate keeps them across rebuilds; without one the app is signed
# ad hoc and macOS asks for both permissions again after every rebuild.
identities=$(security find-identity -v -p codesigning 2>/dev/null || true)
signing_identity="${MUSE_CODESIGN_IDENTITY:-}"
[[ -z "$signing_identity" ]] && signing_identity=$(print -r -- "$identities" | awk '/"Apple Development:/{print $2; exit}')
[[ -z "$signing_identity" ]] && signing_identity=$(print -r -- "$identities" | awk '/"Developer ID Application:/{print $2; exit}')
if [[ -z "$signing_identity" ]]; then
  signing_identity="-"
  print -u2 'No signing certificate found: signing ad hoc. That works, but macOS will ask for'
  print -u2 'Screen Recording and Accessibility again after each rebuild.'
fi
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx15.2 \
  -framework AppKit -framework ScreenCaptureKit -framework MetalKit -framework CoreImage \
  Sources/main.swift Sources/MuseCall.swift -o "$app_dir/Contents/MacOS/MuseFullscreen"
cp Info.plist "$app_dir/Contents/Info.plist"
codesign --force --sign "$signing_identity" --options runtime --timestamp=none "$app_dir"
codesign --verify --strict "$app_dir"
print "Built $app_dir"
