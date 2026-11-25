#!/bin/zsh
# Maintainer only: build, sign with a Developer ID, notarize with Apple and
# staple, so the download opens on any Mac without a Gatekeeper warning.
# Needs a "Developer ID Application" certificate and a notarytool keychain
# profile (xcrun notarytool store-credentials); NOTARY_PROFILE names it.
set -euo pipefail
cd "${0:A:h}"
: "${NOTARY_PROFILE:?set NOTARY_PROFILE to your notarytool keychain profile}"
identity=$(security find-identity -v -p codesigning | awk '/"Developer ID Application:/{print $2; exit}')
[[ -n "$identity" ]] || { print -u2 'No Developer ID Application certificate.'; exit 1; }
MUSE_CODESIGN_IDENTITY="$identity" ./build.sh
app="Muse Fullscreen.app"
codesign --force --sign "$identity" --options runtime --timestamp "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
mkdir -p dist
zip="dist/Muse-Fullscreen-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
spctl --assess --type execute --verbose=2 "$app"
print "Ready: $zip"
