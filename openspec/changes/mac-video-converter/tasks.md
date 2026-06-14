## 1. Project scaffold & ffmpeg bundling

- [x] 1.1 Create a SwiftUI macOS app "Xconvert" (arm64, macOS 13+). *(Built as a SwiftPM executable + `.app` bundle assembled by `build-app.sh`, rather than an `.xcodeproj` — fully CLI-buildable, same result.)*
- [x] 1.2 Set the app to dark appearance (`.preferredColorScheme(.dark)`) and a single fixed-size `WindowGroup`.
- [ ] 1.3 Vendor a static `arm64` `ffmpeg` (incl. `libx264` + `libzimg`), pinned. **BLOCKED:** binary download denied by the sandbox; needs user-authorized source. `vendor-ffmpeg.sh` is ready to run once approved.
- [~] 1.4 Bundle `ffmpeg` at `Contents/Resources/ffmpeg` with executable bit. *(Build script copies + `chmod +x` + signs it automatically when `Vendor/ffmpeg` exists; pending 1.3.)*
- [x] 1.5 Resolve the binary at launch (`FFmpegLocator`): prefer bundled, fall back to system ffmpeg for dev; surfaces a clear error if none found.

## 2. Inspection (AVFoundation)

- [x] 2.1 `SourceInfo` (duration, display size, fps, hasAudio, isHDR) + `VideoInspector.inspect(url:) async throws`.
- [x] 2.2 Read duration via `load(.duration)` and fps via `nominalFrameRate` (async load APIs).
- [x] 2.3 Compute **display** dimensions by applying `preferredTransform` to `naturalSize`.
- [x] 2.4 Detect audio presence via `loadTracks(withMediaType: .audio)` being empty. *(Verified: practice file detected no-audio; test clip detected audio.)*
- [x] 2.5 Detect HDR from the format-description transfer function (HLG / SMPTE-2084); default SDR.
- [x] 2.6 Treat a file with no decodable video track as a "not a video" error (`InspectError.notAVideo`).

## 3. Transcode engine (args + Process + progress)

- [x] 3.1 `FFmpegPlan.build` base chain: `fps=30`, longest-edge bounding-box scale, `yuv420p`, libx264 High, AAC 128k, `+faststart`. *(Verified output: 1280×832 / 720×1280.)*
- [x] 3.2 No-audio branch: `anullsrc` + `-map 0:v:0 -map 1:a:0 -shortest`. *(Verified: practice file got a silent AAC track.)*
- [~] 3.3 HDR branch: `zscale`+`tonemap` chain implemented. **Unverified** — needs a libzimg-enabled ffmpeg (system Homebrew build lacks `zscale`) and an HDR sample.
- [x] 3.4 Output `<source-dir>/<basename>-x.mp4` (`-y`); source untouched. *(Verified.)*
- [x] 3.5 Run via `Process` with `-progress pipe:1 -nostats`; separate stdout/stderr `Pipe`s.
- [x] 3.6 Parse `out_time_us` → 0–1 progress fraction. *(Verified: 0→100% reported.)*
- [x] 3.7 Non-zero exit → failure with stderr tail; never report partial output as success.

## 4. UI & state machine

- [x] 4.1 `Converter` (`ObservableObject`, `@MainActor`) with `.idle/.inspecting/.converting/.done/.error` and async run pipeline.
- [x] 4.2 `ContentView` renders each phase distinctly, dark drop-zone layout.
- [x] 4.3 Drag-and-drop via `.dropDestination(for: URL.self)` with hover feedback; first-of-many.
- [x] 4.4 File picker via `.fileImporter` filtered to video types.
- [x] 4.5 Converting state: determinate `ProgressView` bound to the 0–1 fraction + percent.
- [x] 4.6 Done state: output name + `NSWorkspace…activateFileViewerSelecting` reveal (auto + button).
- [x] 4.7 Error state: human-readable message; "Try Another" to recover.
- [x] 4.8 Convert another after success/error without relaunching (`reset()`).

## 5. Packaging & distribution

- [x] 5.1 App Sandbox not enabled (SwiftPM build adds no sandbox entitlement) → sibling-file writes and embedded-binary launch work.
- [x] 5.2 Hardened Runtime off for v1; ad-hoc signing in `build-app.sh` (`codesign --sign -`).
- [~] 5.3 Confirmed offline (no network code). **Self-contained pending 1.3** (currently falls back to system ffmpeg).

## 6. Verification

- [x] 6.1 Converted the real `3024×1964 @ 120fps` screen recording → `1280×832`, 30fps, H.264 High, `yuv420p`, AAC. ✓
- [~] 6.2 No-audio → silent AAC track ✓ verified. HDR natural colors — **not verified** (see 3.3).
- [x] 6.3 Portrait `1080×1920` → `720×1280`, longest-edge cap + aspect preserved ✓ (via bundled app binary).
- [ ] 6.4 End-to-end upload to X (`POST /2/tweets` accepts converted, rejects original) — **must be done by the user** (no X access here).
- [ ] 6.5 First-launch via right-click → Open (Gatekeeper) — to confirm after a self-contained build is produced.
