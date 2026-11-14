#!/usr/bin/env bash
#
# Builds a drag-to-Applications .dmg with the "Seed-VC" launcher app.
#
#   ./packaging/build-dmg.sh --version 0.1.0
#
# The .app embeds this repository (Resources/app). On first launch the launcher
# copies it to ~/Library/Application Support/Seed-VC and delegates the Python
# setup to the repository's own start-mac.command.
#
set -euo pipefail

VERSION="0.1.0"
OUT="dist"

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --out)     OUT="$2";     shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Seed-VC"
STAGE="$OUT/staging"
BUNDLE="$STAGE/$APP_NAME.app"
DMG="$OUT/Seed-VC-${VERSION}-macos.dmg"

echo "==> version $VERSION"
rm -rf "$STAGE" "$DMG"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

sed "s/__VERSION__/${VERSION}/" "$ROOT/packaging/launcher.sh" > "$BUNDLE/Contents/MacOS/SeedVC"
chmod +x "$BUNDLE/Contents/MacOS/SeedVC"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>local.seedvc.launcher</string>
  <key>CFBundleExecutable</key><string>SeedVC</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> embedding sources"
mkdir -p "$BUNDLE/Contents/Resources/app"
rsync -a \
  --exclude '.git' \
  --exclude '.venv' \
  --exclude 'dist' \
  --exclude '__pycache__' \
  --exclude 'my_models' \
  --exclude 'packaging' \
  "$ROOT/" "$BUNDLE/Contents/Resources/app/"
chmod +x "$BUNDLE/Contents/Resources/app/start-mac.command" \
         "$BUNDLE/Contents/Resources/app/start-mac-Roman" 2>/dev/null || true

if [ -f "$ROOT/packaging/icon.icns" ]; then
  cp "$ROOT/packaging/icon.icns" "$BUNDLE/Contents/Resources/icon.icns"
fi

echo "==> signing (ad-hoc)"
codesign --force --deep --sign - "$BUNDLE" >/dev/null 2>&1 || echo "   warning: codesign failed"
codesign --verify --deep --strict "$BUNDLE" 2>/dev/null && echo "   signature ok"

ln -s /Applications "$STAGE/Applications"
echo "==> building dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> $DMG ($(du -h "$DMG" | cut -f1))"
shasum -a 256 "$DMG" | tee "$DMG.sha256"
