#!/bin/zsh
# Builds build/mousemallow.app and refreshes the images in assets/.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/mousemallow.app"
TMP="build/tmp"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$TMP" assets

echo "Compiling app…"
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
  Sources/main.swift Sources/Brand.swift -o "$TMP/mousemallow-arm64"
swiftc -O -swift-version 5 -target x86_64-apple-macos14.0 \
  Sources/main.swift Sources/Brand.swift -o "$TMP/mousemallow-x86_64"
lipo -create "$TMP/mousemallow-arm64" "$TMP/mousemallow-x86_64" -output "$APP/Contents/MacOS/mousemallow"

echo "Rendering logo and icon…"
swiftc -parse-as-library Sources/Brand.swift Tools/render_assets.swift -o "$TMP/render_assets"
"$TMP/render_assets" assets >/dev/null

ICONSET="$TMP/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s assets/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) assets/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cp Info.plist "$APP/Contents/Info.plist"
cp Resources/Sniglet-Regular.ttf Resources/OFL.txt "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null
echo "Built: $PWD/$APP"
