#!/bin/bash
# Download a static arm64 ffmpeg into Vendor/ so build-app.sh can embed it,
# making the app fully self-contained. Pass an alternate URL as $1 if desired.
# Verifies libx264 (required) and libzimg/zscale (needed for HDR tonemapping).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
URL="${1:-https://www.osxexperts.net/ffmpeg81arm.zip}"
mkdir -p "$ROOT/Vendor"
TMP="$(mktemp -d)"

echo "==> downloading $URL"
curl -fL -o "$TMP/ffmpeg.zip" "$URL"
unzip -o -q "$TMP/ffmpeg.zip" -d "$TMP"
mv "$TMP/ffmpeg" "$ROOT/Vendor/ffmpeg"
chmod +x "$ROOT/Vendor/ffmpeg"
rm -rf "$TMP"

echo "==> verifying capabilities"
"$ROOT/Vendor/ffmpeg" -hide_banner -encoders 2>/dev/null | grep -q libx264 \
    && echo "    libx264 ✓" || { echo "    libx264 MISSING — unusable"; exit 1; }
"$ROOT/Vendor/ffmpeg" -hide_banner -filters 2>/dev/null | grep -q zscale \
    && echo "    zscale (HDR) ✓" || echo "    zscale MISSING — HDR tonemap won't work (SDR still fine)"

echo "==> link check (should be system libs only for a static build)"
otool -L "$ROOT/Vendor/ffmpeg" | sed -n '2,15p'

echo "==> done. Now run ./build-app.sh to produce a self-contained Xconvert.app"
