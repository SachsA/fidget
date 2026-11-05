#!/usr/bin/env bash
# Builds universal (arm64 + x86_64) binaries, assembles Fidget.app and packages release archives in dist/.
# Usage: scripts/build.sh [version]
# Set CODESIGN_IDENTITY to a "Developer ID Application" identity to sign for distribution;
# defaults to ad-hoc signing.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
IDENTITY="${CODESIGN_IDENTITY:--}"
ARCHS=(--arch arm64 --arch x86_64)

# Keep the version reported by the binaries in sync with the release tag.
sed -i '' "s/public static let version = \".*\"/public static let version = \"$VERSION\"/" Sources/FidgetCore/Settings.swift

swift build -c release "${ARCHS[@]}" --product FidgetApp
swift build -c release "${ARCHS[@]}" --product fidget
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

rm -rf dist && mkdir -p dist
APP="dist/Fidget.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/FidgetApp" "$APP/Contents/MacOS/Fidget"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"

# App icon from the 1024px master
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s assets/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) assets/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cp "$BIN/fidget" dist/fidget
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" dist/fidget
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"

(
  cd dist
  ditto -c -k --keepParent Fidget.app "Fidget-$VERSION.zip"
  tar -czf "fidget-cli-$VERSION.tar.gz" fidget
  shasum -a 256 "Fidget-$VERSION.zip" "fidget-cli-$VERSION.tar.gz" > SHA256SUMS
)
echo "Built Fidget $VERSION (build $BUILD) in dist/"
cat dist/SHA256SUMS
