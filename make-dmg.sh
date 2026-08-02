#!/bin/bash

set -euo pipefail

APP_NAME="Rocket Proxy Checker"
VOLUME="Rocket Proxy Checker"
DMG_NAME="RocketProxyChecker"
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/$APP_NAME.app"
DMG="$ROOT/$DMG_NAME.dmg"

if [ ! -d "$APP" ]; then
    echo "✗ $APP_NAME.app not found. Run ./build-app.sh first." >&2
    exit 1
fi

echo "→ Staging disk image contents…"
STAGING="$(mktemp -d)/$VOLUME"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"

ln -s /Applications "$STAGING/Applications"

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$STAGING/.VolumeIcon.icns"
    if command -v SetFile >/dev/null 2>&1; then
        SetFile -a C "$STAGING" 2>/dev/null || true
    fi
fi

echo "→ Building $DMG_NAME.dmg…"
rm -f "$DMG"
hdiutil create \
    -volname "$VOLUME" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    "$DMG" >/dev/null

rm -rf "$(dirname "$STAGING")"

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo "✓ Built $DMG_NAME.dmg ($SIZE)"
