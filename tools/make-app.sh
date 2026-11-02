#!/bin/sh
# Assemble Patchwork.app from the SwiftPM release build, with optional Developer ID signing and notarisation.
#
#   tools/make-app.sh                       build + bundle (unsigned, runs locally)
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" tools/make-app.sh
#   ... plus NOTARY_PROFILE=<keychain profile from `xcrun notarytool store-credentials`> to notarise + staple
#
# Output: dist/Patchwork.app and dist/patchwork (CLI), plus dist/Patchwork-<version>.zip
set -eu
cd "$(dirname "$0")/.."
# Version: VERSION env -> latest tag (v1.2.3 -> 1.2.3) -> 0.0.0-<commit> -> 0.0.0
if [ -z "${VERSION:-}" ]; then
  if tag=$(git describe --tags --exact-match 2>/dev/null); then VERSION="${tag#v}"
  elif hash=$(git rev-parse --short HEAD 2>/dev/null); then VERSION="0.0.0-$hash"
  else VERSION="0.0.0"; fi
fi
BUNDLE_ID="${BUNDLE_ID:-media.monstrous.patchwork}"
MIN_OS="13.0"

echo "building release..."
swift build -c release --product PatchworkApp
swift build -c release --product patchwork
BIN=.build/release

rm -rf dist && mkdir -p dist
APP=dist/Patchwork.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/PatchworkApp" "$APP/Contents/MacOS/Patchwork"
cp "$BIN/patchwork" dist/patchwork
# SwiftPM resource bundle (the guide) - Bundle.module looks for it in Contents/Resources
for b in "$BIN"/*.bundle; do [ -d "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done

# Icon: build an .icns from assets/icon-1024.png if the tools are present
if [ -f assets/icon-1024.png ] && command -v iconutil >/dev/null; then
  ICONSET=dist/Patchwork.iconset; mkdir -p "$ICONSET"
  for sz in 16 32 128 256 512; do
    sips -z $sz $sz assets/icon-1024.png --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
    dbl=$((sz*2)); sips -z $dbl $dbl assets/icon-1024.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Patchwork.icns" && rm -rf "$ICONSET"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Patchwork</string>
  <key>CFBundleDisplayName</key><string>Patchwork</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>Patchwork</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>Patchwork</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT licence</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
</dict></plist>
PLIST

if [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "signing with ${SIGN_IDENTITY}..."
  codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" dist/patchwork
  codesign --force --deep --options runtime --timestamp --sign "${SIGN_IDENTITY}" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
fi

ZIP="dist/Patchwork-$VERSION.zip"
( cd dist && ditto -c -k --keepParent Patchwork.app "../$ZIP" )

if [ -n "${SIGN_IDENTITY:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "notarising..."
  xcrun notarytool submit "$ZIP" --keychain-profile "${NOTARY_PROFILE}" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"; ( cd dist && ditto -c -k --keepParent Patchwork.app "../$ZIP" )
fi
echo "done: $APP, dist/patchwork, $ZIP"
