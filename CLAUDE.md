# CLAUDE.md — agent guide for Xconvert

Audience: AI coding agents. This is the fast path to being productive here. Read
this before editing. (`README.md` is the human-facing version.)

## What this is

A tiny, **fully-local macOS app**: drop a video → get an **X (Twitter)-ready MP4**
written as `<name>-x.mp4` next to the original. It exists because X silently
rejects out-of-spec tweet video (`400 "Your media IDs are invalid"`) — notably
Mac ProMotion screen recordings (e.g. `3024×1964 @ 120 fps`). It's a thin,
reliable wrapper around a **validated ffmpeg command**.

No network, no API, no telemetry. Single purpose. Personal tool.

## The conversion contract (do not regress this)

Output MUST satisfy X tweet-video spec: **MP4, H.264 High, AAC, `yuv420p`,
`+faststart`, ≤1280 on the longest edge, ≤30 fps.** The known-good ffmpeg command
(SDR, source has audio):

```
ffmpeg -y -i IN \
  -vf "fps=30,scale=w=1280:h=1280:force_original_aspect_ratio=decrease:force_divisible_by=2,format=yuv420p" \
  -c:v libx264 -profile:v high -preset veryfast -b:v 5M -maxrate 6M -bufsize 8M \
  -c:a aac -b:a 128k -movflags +faststart -progress pipe:1 -nostats  OUT
```

Two inspection-driven branches (everything else is unconditional):
1. **No audio track** → add `-f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100`
   and `-map 0:v:0 -map 1:a:0 -shortest` (X requires an audio track).
2. **HDR (HLG/PQ)** → prepend a `zscale`+`tonemap` chain before `format=yuv420p`.
   Requires an ffmpeg with **libzimg** (`zscale`). The engine auto-detects this
   (`FFmpegCapabilities`) and **falls back to plain SDR** when absent — still
   in-spec, just not tonemapped. Don't make HDR hard-fail.

The scale box caps the **longest** edge, so portrait and landscape both stay in
spec. `fps=30` and the scale box are no-ops when the source is already small/slow,
so we always transcode (no "smart skip").

## Architecture

Native SwiftUI app built as a **SwiftPM executable**, then assembled into a
`.app` bundle by `build-app.sh` (there is **no `.xcodeproj`** — keep it that way;
it's intentionally CLI-buildable). Engine is **hybrid**: AVFoundation inspects,
bundled ffmpeg transcodes.

```
Sources/Xconvert/
  App.swift            @main entry. Gates headless `--convert <path>` vs GUI; defines the App scene.
  ContentView.swift    SwiftUI dark drop-zone UI; renders by Converter.phase.
  Converter.swift      @MainActor ObservableObject. State machine + run pipeline.
                       Phase = .idle | .inspecting | .converting(Double) | .done(URL) | .error(String)
  VideoInspector.swift AVFoundation inspect -> SourceInfo (duration, display size, fps, hasAudio, isHDR).
  FFmpeg.swift         FFmpegLocator (find binary), FFmpegCapabilities (filter detection),
                       FFmpegPlan.build (args), FFmpegRunner (Process + progress + stderr tail).
  CLI.swift            Headless mode — reuses the exact GUI pipeline. This is the test harness.
Resources/
  Info.plist           Bundle metadata (CFBundleIconFile=AppIcon, LSMinimumSystemVersion 13.0).
  AppIcon.icns         App icon (embedded by build-app.sh).
build-app.sh           swift build -> assemble .app -> embed ffmpeg + icon -> ad-hoc codesign.
vendor-ffmpeg.sh       Download a static arm64 ffmpeg into Vendor/ (gitignored). Verifies libx264/zscale.
openspec/              Spec-driven change history (see "OpenSpec" below).
```

`FFmpegLocator.resolve()` prefers the **bundled** `Contents/Resources/ffmpeg`,
falling back to a system ffmpeg (`/opt/homebrew/bin/ffmpeg`, …) — the fallback is
a dev convenience; the shipped app is self-contained.

## Build / run / test

```sh
./vendor-ffmpeg.sh           # one-time: fetch static ffmpeg into Vendor/ (gitignored)
./build-app.sh               # -> build/Xconvert.app (release, arm64, signed, icon+ffmpeg embedded)
swift build                  # quick compile check (debug)

# Headless end-to-end test — the canonical way to verify a change:
build/Xconvert.app/Contents/MacOS/Xconvert --convert /path/to/video.mov
#   stdout = output path; stderr = inspect summary + progress
# Then probe:
ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate,pix_fmt,profile -of default OUT
```

There is no XCTest suite. **Verify by converting a real file via `--convert` and
probing the output** against the contract above. Good test inputs to cover:
high-res/high-fps no-audio (the canonical case), portrait-with-audio (longest-edge
+ audio-preserve), already-small clips (no upscale).

## Conventions & constraints

- **arm64**, **macOS 13+**, dark mode only.
- SwiftPM uses **Swift 5 language mode** (`swift-tools-version:5.9`) — relaxed
  concurrency. The Process I/O handlers use a lock-guarded collector
  (`ProcessOutputCollector`); keep them `@unchecked Sendable`-safe.
- **App Sandbox is OFF** and **Hardened Runtime is OFF** (ad-hoc signed). Needed
  to write sibling files and launch the embedded binary. Don't add a sandbox
  entitlement.
- The source file is never modified; output overwrites `<name>-x.mp4` (`-y`).
- Match the surrounding code's style (small enums/structs, no external deps).

## Gotchas (will waste your time if unknown)

- **SourceKit shows false "Cannot find X in scope" errors** across files until
  the package is built. Trust `swift build`, not the live diagnostics.
- AVFoundation's `nominalFrameRate` can misreport VFR/screen recordings (e.g. 28
  instead of 120). Harmless — we always force `fps=30`. Don't gate logic on it.
- The bundled osxexperts static ffmpeg has **libx264 but not libzimg/zscale**, so
  HDR tonemapping currently falls back to SDR. For true HDR, vendor a
  libzimg-enabled static arm64 ffmpeg: `./vendor-ffmpeg.sh <url>` (engine
  auto-switches the tonemap chain on when `zscale` is present).
- `Vendor/ffmpeg` is gitignored — it is NOT in the repo. Run `vendor-ffmpeg.sh`
  before `build-app.sh`, or the app falls back to a system ffmpeg.
- Use the AVFoundation **async** load APIs (`load(_:)`, `loadTracks`), not the
  deprecated synchronous `asset.tracks`.

## OpenSpec workflow

This project is spec-driven. The change lives at
`openspec/changes/mac-video-converter/` (`proposal.md`, `design.md`,
`specs/{video-conversion,converter-ui,app-distribution}/spec.md`, `tasks.md`).
`design.md` has the decision rationale (D1–D9) and open questions. When changing
behavior, update the relevant spec + tasks rather than only the code. Useful:
`openspec status --change mac-video-converter`, `openspec validate <change> --strict`.

## Known follow-ups (not done)

- **Verify on X** (`POST /2/tweets` accepts a converted file) — requires X access;
  user-side.
- **True HDR tonemap** — needs a libzimg ffmpeg build (see gotchas).
- Not built (intentionally out of v1 scope): batch/folder, Finder Quick Action,
  notarized distribution, Intel/universal build, in-app trimming.
