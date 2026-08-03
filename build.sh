#!/bin/bash
# Build ShotEditor and assemble a proper macOS .app bundle (LSUIElement agent).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${1:-release}"          # debug | release
APP_NAME="ShotEditor"
BUILD_DIR="$ROOT/.build/$CONFIG"
APP_BUNDLE="$ROOT/$APP_NAME.app"

echo "▸ Compiling ($CONFIG)…"
swift build -c "$CONFIG" --package-path "$ROOT"

# Generate the app icon (.icns) once, from the just-built binary.
if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
    echo "▸ Generating app icon…"
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    BASE_PNG="$(mktemp -d)/icon-1024.png"
    "$BUILD_DIR/$APP_NAME" --makeicon "$BASE_PNG" || true
    if [ -f "$BASE_PNG" ]; then
        for s in 16 32 64 128 256 512; do
            sips -z $s $s "$BASE_PNG" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
            d=$((s*2)); sips -z $d $d "$BASE_PNG" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
        done
        iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns" || true
    fi
fi

echo "▸ Assembling $APP_NAME.app…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Optional resources (icon etc.)
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Prefer a stable self-signed identity so Screen Recording permission persists
# across rebuilds. Falls back to ad-hoc (which re-prompts on every build).
SIGN_IDENTITY="ShotEditor Local Signing"
# `-v` hides self-signed (untrusted) identities, so match without it.
if [ "${SHOTEDITOR_ADHOC:-0}" != "1" ] && \
   security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    echo "▸ Code signing with '$SIGN_IDENTITY' (first time: click 'Always Allow')…"
    SIGN_AS="$SIGN_IDENTITY"
else
    echo "▸ Code signing (ad-hoc — run scripts/create-signing-cert.sh once so"
    echo "  Screen Recording permission stops resetting every build)…"
    SIGN_AS="-"
fi
codesign --force --deep --sign "$SIGN_AS" \
    --entitlements "$ROOT/Resources/ShotEditor.entitlements" \
    "$APP_BUNDLE" 2>/dev/null || \
    codesign --force --deep --sign "$SIGN_AS" "$APP_BUNDLE"

echo "✓ Built: $APP_BUNDLE"
