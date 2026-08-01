#!/bin/bash
# Builds "Proxy Checker.app" for Apple silicon.
# Usage:  ./build-app.sh   then open "./Proxy Checker.app"

set -euo pipefail

# The bundle is what Finder labels, so it carries the spaced name. The binary
# inside keeps the SwiftPM target name.
APP_NAME="Proxy Checker"
BINARY="ProxyChecker"
BUNDLE_ID="dev.local.proxychecker"
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/$APP_NAME.app"

echo "→ Building release binary (arm64)…"
swift build -c release --arch arm64 --package-path "$ROOT"

BIN="$(swift build -c release --arch arm64 --package-path "$ROOT" --show-bin-path)/$BINARY"

echo "→ Assembling $APP_NAME.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$BINARY"

# Icon. Regenerate from Icon.png when possible, so swapping that one picture is
# enough to change the icon; otherwise fall back to the committed .icns.
ICON_INSTALLED=0
if [ -f "$ROOT/Resources/Icon.png" ] && command -v iconutil >/dev/null 2>&1; then
    echo "→ Generating icon from Icon.png…"
    ICONSET_PARENT="$(mktemp -d)"
    ICONSET="$ICONSET_PARENT/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
                "128 128x128" "256 128x128@2x" "256 256x256" \
                "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
        set -- $spec
        sips -z "$1" "$1" "$ROOT/Resources/Icon.png" \
             --out "$ICONSET/icon_$2.png" >/dev/null 2>&1
    done
    if iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
        ICON_INSTALLED=1
    fi
    rm -rf "$ICONSET_PARENT"
fi

if [ "$ICON_INSTALLED" -eq 0 ] && [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    echo "→ Using prebuilt AppIcon.icns…"
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    ICON_INSTALLED=1
fi

[ "$ICON_INSTALLED" -eq 1 ] || echo "  (no icon found — building without one)"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>        <string>$BINARY</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>           <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundleIconName</key>          <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSSupportsAutomaticTermination</key><true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key><true/>
    </dict>
</dict>
</plist>
PLIST

echo "→ Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  (ad-hoc signing skipped)"

# Finder and the Dock cache icons aggressively; touching the bundle nudges them.
touch "$APP"

echo "✓ Built $APP"
echo "  open \"$APP\""
