## 1. Project scaffold & ffmpeg bundling

- [ ] 1.1 Create an Xcode SwiftUI macOS app target "Xconvert" (arm64, deployment target macOS 13 Ventura+).
- [ ] 1.2 Set the app to dark appearance (`.preferredColorScheme(.dark)`) and a single fixed-ish `WindowGroup`.
- [ ] 1.3 Vendor a static `arm64` `ffmpeg` build that includes `libx264` and `libzimg`; verify with `ffmpeg -hide_banner -encoders | grep libx264` and `ffmpeg -hide_banner -filters | grep zscale`; pin the version.
- [ ] 1.4 Add `ffmpeg` to *Copy Bundle Resources* at `Contents/Resources/ffmpeg`; ensure the executable bit survives (build-phase `chmod +x`, plus runtime `chmod` fallback).
- [ ] 1.5 Resolve and sanity-check the bundled binary path at launch (`Bundle.main.url(forResource:"ffmpeg",withExtension:nil)`), failing loudly if missing/not executable.

## 2. Inspection (AVFoundation)

- [ ] 2.1 Define a `SourceInfo` value (duration seconds, display size, fps, hasAudio, isHDR) and an `inspect(url:) async throws -> SourceInfo`.
- [ ] 2.2 Read duration via `load(.duration)` and frame rate via the video track `nominalFrameRate` (async load APIs, not the deprecated `asset.tracks`).
- [ ] 2.3 Compute **display** dimensions by applying `preferredTransform` to `naturalSize` so rotated/portrait clips report true size.
- [ ] 2.4 Detect audio presence via `loadTracks(withMediaType: .audio)` being empty.
- [ ] 2.5 Detect HDR from the video track's format-description transfer function (HLG / SMPTE-2084); default to SDR when uncertain.
- [ ] 2.6 Treat a file that yields no decodable video track as an "unsupported / not a video" error.

## 3. Transcode engine (args + Process + progress)

- [ ] 3.1 Implement `buildArgs(for: SourceInfo, input:, output:)` producing the base chain: `fps=30`, longest-edge bounding-box `scale=w=1280:h=1280:force_original_aspect_ratio=decrease:force_divisible_by=2`, `format=yuv420p`, libx264 High `-preset veryfast -b:v 5M -maxrate 6M -bufsize 8M`, AAC 128k, `+faststart`.
- [ ] 3.2 No-audio branch: add `-f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100`, `-map 0:v:0 -map 1:a:0 -shortest`.
- [ ] 3.3 HDR branch: swap in the `zscale`+`tonemap` chain before `format=yuv420p` (per design D3); SDR path skips it.
- [ ] 3.4 Derive output path as `<source-dir>/<basename>-x.mp4` (overwrite with `-y`); never touch the source file.
- [ ] 3.5 Run `ffmpeg` via `Process` with `-progress pipe:1 -nostats`; capture stdout and stderr on separate `Pipe`s.
- [ ] 3.6 Parse `out_time_us` from the stdout progress stream and divide by `duration*1_000_000` to publish a 0–1 progress fraction.
- [ ] 3.7 Treat non-zero exit as failure; surface an error containing the tail of stderr; do not present partial output as success.

## 4. UI & state machine

- [ ] 4.1 Define `Converter` (`@Observable`) with `phase: .idle | .inspecting | .converting(Double) | .done(URL) | .error(String)` and a `convert(url:) async` that runs inspect → buildArgs → run → reveal.
- [ ] 4.2 Build `ContentView` rendering each phase distinctly with a dark, legible drop-zone layout.
- [ ] 4.3 Drag-and-drop: `.dropDestination(for: URL.self)` with hover feedback; on multiple files, take the first and ignore the rest.
- [ ] 4.4 File picker: `.fileImporter` filtered to video content types (`.movie`, `.video`, `.quickTimeMovie`, `.mpeg4Movie`).
- [ ] 4.5 Converting state: show a determinate progress indicator bound to the engine's 0–1 fraction.
- [ ] 4.6 Done state: show the output file name and reveal it via `NSWorkspace.shared.activateFileViewerSelecting([out])`.
- [ ] 4.7 Error state: show a clear, human-readable message (unsupported file vs conversion failure) and allow trying another file.
- [ ] 4.8 Allow converting another file after success/error without relaunching (reset to `.idle` on new input).

## 5. Packaging & distribution

- [ ] 5.1 Disable App Sandbox in entitlements (so sibling-file writes and embedded-binary launch are allowed).
- [ ] 5.2 Leave Hardened Runtime off for v1; configure ad-hoc / personal code signing.
- [ ] 5.3 Confirm the built app is fully offline and self-contained (no network calls; works with Wi-Fi off and no system `ffmpeg`).

## 6. Verification

- [ ] 6.1 Convert a real out-of-spec clip (e.g. a `3024×1964 @ 120 fps` screen recording) and verify the output is ≤1280 longest edge, 30 fps, H.264 High + AAC, `yuv420p` via `ffprobe`/`mediainfo`.
- [ ] 6.2 Verify the no-audio path produces a file with a silent AAC track, and the HDR path produces natural (non-washed) SDR colors.
- [ ] 6.3 Verify a portrait clip respects the longest-edge cap and preserves aspect.
- [ ] 6.4 End-to-end: upload a converted `<name>-x.mp4` to X and confirm `POST /2/tweets` accepts it (the original out-of-spec clip does not).
- [ ] 6.5 Verify first-launch via right-click → Open works, and subsequent launches open normally.
