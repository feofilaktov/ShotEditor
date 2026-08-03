#!/bin/bash
# Build a universal (Intel + Apple Silicon) ShotEditor.app and package it into a
# distributable .dmg with an Applications drop target.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP_NAME="ShotEditor"
APP="$ROOT/$APP_NAME.app"
DMG="$ROOT/dist/$APP_NAME.dmg"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo 0.1.0)"

echo "▸ Building universal release ($VERSION)…"
swift build -c release --arch arm64 --arch x86_64 >/dev/null
BIN="$ROOT/.build/apple/Products/Release/$APP_NAME"
[ -f "$BIN" ] || { echo "universal binary not found at $BIN"; exit 1; }

# --- Icon (generate once) ---
if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
    echo "▸ Generating app icon…"
    ICONSET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET"
    BASE_PNG="$(mktemp -d)/icon-1024.png"
    "$BIN" --makeicon "$BASE_PNG" || true
    if [ -f "$BASE_PNG" ]; then
        for s in 16 32 64 128 256 512; do
            sips -z $s $s "$BASE_PNG" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
            d=$((s*2)); sips -z $d $d "$BASE_PNG" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
        done
        iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns" || true
    fi
fi

echo "▸ Assembling $APP_NAME.app (universal)…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"

# --- Sign ---
SIGN_IDENTITY="ShotEditor Local Signing"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    SIGN_AS="$SIGN_IDENTITY"; echo "▸ Signing with '$SIGN_IDENTITY'…"
else
    SIGN_AS="-"; echo "▸ Signing ad-hoc (users will need right-click → Open the first time)…"
fi
codesign --force --deep --options runtime --sign "$SIGN_AS" \
    --entitlements "$ROOT/Resources/ShotEditor.entitlements" "$APP" 2>/dev/null || \
    codesign --force --deep --sign "$SIGN_AS" "$APP"

# --- DMG ---
echo "▸ Building .dmg…"
mkdir -p "$ROOT/dist"
STAGE="$(mktemp -d)/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "✓ Built: $DMG"
echo "  Universal: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
echo
echo "Distribute this .dmg. First-launch note for users (unsigned build):"
echo "  right-click ShotEditor.app → Open → Open, then grant Screen Recording."
