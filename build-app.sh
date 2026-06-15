#!/bin/bash
# Build Xconvert.app: compile the SwiftPM executable, assemble a proper .app
# bundle, embed the bundled ffmpeg (if vendored), and ad-hoc code-sign it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/Xconvert.app"

echo "==> swift build ($CONFIG, arm64)"
swift build -c "$CONFIG" --arch arm64
BIN_DIR="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Xconvert" "$APP/Contents/MacOS/Xconvert"
chmod +x "$APP/Contents/MacOS/Xconvert"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    echo "==> added app icon"
fi

if [ -f "$ROOT/Vendor/ffmpeg" ]; then
    cp "$ROOT/Vendor/ffmpeg" "$APP/Contents/Resources/ffmpeg"
    chmod +x "$APP/Contents/Resources/ffmpeg"
    echo "==> bundled Vendor/ffmpeg (self-contained)"
else
    echo "==> WARNING: Vendor/ffmpeg missing — app will fall back to a system ffmpeg"
fi

# Ad-hoc sign (unsandboxed; no Hardened Runtime for v1). Sign the embedded
# binary first, then the app.
if [ -f "$APP/Contents/Resources/ffmpeg" ]; then
    codesign --force --sign - "$APP/Contents/Resources/ffmpeg"
fi
codesign --force --deep --sign - "$APP"

echo "==> done: $APP"
