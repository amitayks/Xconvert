# Xconvert

A tiny, fully-local macOS app: **drop a video → get an X (Twitter)-ready MP4**.

X silently rejects out-of-spec tweet video (`400 "Your media IDs are invalid"`) —
e.g. Mac ProMotion screen recordings at `3024×1964 @ 120 fps`. Xconvert transcodes
any video to X's tweet-video spec (≤1280 longest edge, 30 fps, H.264 High + AAC,
`yuv420p`, `+faststart`) and writes `<name>-x.mp4` next to the original.

## How it works

- **SwiftUI** dark-mode drop-zone app.
- **AVFoundation** inspects the source (duration, dimensions, fps, audio, HDR).
- **ffmpeg** does the transcode, with two inspection-driven branches:
  - no audio track → inject a silent AAC track (X requires audio),
  - HDR (HLG/PQ) → tonemap to SDR.
- Longest-edge scaling handles landscape *and* portrait.

## Build

```sh
./vendor-ffmpeg.sh     # download a static arm64 ffmpeg into Vendor/ (one time)
./build-app.sh         # build build/Xconvert.app (embeds ffmpeg, ad-hoc signs)
open build/Xconvert.app
```

First launch: right-click → Open to clear Gatekeeper (ad-hoc signed for personal use).

Without `Vendor/ffmpeg`, the app falls back to a system `ffmpeg` (e.g. Homebrew) —
handy for development, but not self-contained.

## Headless / testing

```sh
build/Xconvert.app/Contents/MacOS/Xconvert --convert /path/to/video.mov
# prints the output path on stdout; same pipeline as the GUI
```

## Requirements

- Apple-silicon Mac, macOS 13+.
- A static `arm64` ffmpeg with `libx264` (and `libzimg`/`zscale` for HDR) to bundle.
