## Context

Xconvert is a brand-new, single-purpose macOS app: drop a video, get back a file that X (Twitter) will accept on `POST /2/tweets`. It exists because X silently rejects out-of-spec tweet video (`400 "Your media IDs are invalid"`), with Mac ProMotion screen recordings (`3024×1964 @ 120 fps`) as the confirmed trigger. The fix is a fast, local, native transcode to X's spec.

This is a personal tool with a tiny surface area, so the design optimizes for **reliability of the output** (the one thing that must not break) and **a self-contained, offline app** over portability or distribution polish. The transcode command in this document is already validated end-to-end: a file produced by it posted to X successfully, whereas the original clip did not.

Constraints:
- Apple-silicon Mac, built in Xcode with SwiftUI.
- No network, no API, no dependency on MusePostBot or any posting service.
- Must work on a Mac with no Homebrew / no system `ffmpeg`.

## Goals / Non-Goals

**Goals:**
- Drop or pick a video → produce `<name>-x.mp4` next to it in ~1–2 s for typical clips.
- Output is guaranteed-postable to X: MP4 / H.264 High / AAC / `yuv420p` / `+faststart`, ≤1280 longest edge, ≤30 fps.
- Correct across the real variations: landscape & portrait, audio & silent, HDR & SDR.
- Self-contained and fully offline (bundled static `ffmpeg`, no external install).
- Clear dark-mode UI with idle → inspecting → converting → done/error states and Finder reveal.

**Non-Goals (v1):**
- Batch / folder conversion; Finder Quick Action / Services entry.
- Notarized public distribution; Intel or universal builds.
- "Smart skip if already in spec" (we always transcode — see D8).
- In-app trimming/editing, format choices, or quality settings.
- Cross-platform (Windows/Linux).

## Decisions

### D1 — Native SwiftUI app (not Tauri / Electron / shell script)

A native SwiftUI app gives the most Mac-native feel, free dark mode, native drag-and-drop, and lets us use AVFoundation directly for inspection. Alternatives considered: a shell-script + Finder Quick Action (no real UI, fails the "nice dark-mode app" goal); Tauri (React shell — smaller learning gap for a web dev, but pulls in Rust + a webview for a tool that benefits from native AVFoundation); Electron (familiar but heavy, no native media APIs). SwiftUI was chosen deliberately, accepting the Swift/Xcode learning curve as part of the project's value.

### D2 — Hybrid engine: AVFoundation inspects, bundled `ffmpeg` transcodes

Inspection (duration, dimensions, fps, audio presence, color transfer) is done natively with **AVFoundation (AVAsset)**; the actual transcode is done by a **bundled static `ffmpeg`** invoked via `Process`, using the validated command.

Alternatives considered:
- **Pure AVFoundation / VideoToolbox** (no bundled binary): smallest app, hardware-accelerated, most native. Rejected for v1 because `AVAssetExportSession` is preset-based and won't reliably give the exact combination we need (fps cap + longest-edge scale + `yuv420p` + silent-audio injection + `+faststart`); reproducing it via a full `AVAssetReader`/`AVAssetWriter` pipeline is a lot of Swift and risks re-creating the exact out-of-spec bug we are escaping. The whole point of the app is a *known-good* output.
- **Bundle `ffmpeg` + `ffprobe`** (the original handoff plan): two binaries to vendor/sign, and JSON parsing for inspection. Rejected because AVFoundation already gives us everything `ffprobe` would, natively and without a second binary.

The hybrid keeps the validated `ffmpeg` output while replacing `ffprobe` with clean native inspection — one bundled binary instead of two.

### D3 — The transcode command and its two branches

Base command (source **has audio**, **SDR**):
```
ffmpeg -y -i IN \
  -vf "fps=30,scale=w=1280:h=1280:force_original_aspect_ratio=decrease:force_divisible_by=2,format=yuv420p" \
  -c:v libx264 -profile:v high -preset veryfast -b:v 5M -maxrate 6M -bufsize 8M \
  -c:a aac -b:a 128k -movflags +faststart \
  -progress pipe:1 -nostats \
  "<name>-x.mp4"
```

Only two things branch off inspection; everything else is one unconditional chain (the `fps`/`scale` filters are no-ops when the source is already small/slow, so we don't bother detecting "already compliant" — re-encoding a short clip is cheap):

1. **No audio track** → add a generated silent track:
   ```
   ... -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
   -map 0:v:0 -map 1:a:0 -shortest -c:a aac -b:a 128k ...
   ```
   (X generally requires an audio track; this was validated end-to-end.)
2. **HDR source (HLG/PQ transfer)** → tonemap to SDR before `format=yuv420p`, replacing the video filter chain with:
   ```
   fps=30,zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,scale=w=1280:h=1280:force_original_aspect_ratio=decrease:force_divisible_by=2,format=yuv420p
   ```
   This requires the bundled `ffmpeg` to include **libzimg** (`zscale`). SDR sources skip the tonemap entirely.

### D4 — Longest-edge scaling (refines the original validated filter)

The original validated filter was `scale='min(1280,iw)':-2`, which only caps **width**. A portrait `1080×1920` clip would pass through at `1080×1920` and could exceed X's height limit. We use a bounding-box scale instead: `scale=w=1280:h=1280:force_original_aspect_ratio=decrease:force_divisible_by=2`, which caps the **longest** edge to 1280 for both orientations, preserves aspect, and forces even dimensions (required for `yuv420p`/H.264). This is a deliberate, low-risk improvement over the original command.

### D5 — Inspection → argument mapping

| Signal | Read via AVFoundation | Effect on args |
|---|---|---|
| Frame rate | video track `nominalFrameRate` | always add `fps=30` |
| Display dimensions | `naturalSize` **applied to `preferredTransform`** (so rotated/portrait clips report true display size) | bounding-box `scale` (D4) |
| Audio presence | `loadTracks(withMediaType: .audio)` empty? | empty → `anullsrc` + `-map`/`-shortest`; else `-c:a aac` |
| Color transfer | track `formatDescriptions` → transfer-function extension (HLG / SMPTE-2084) | HDR → tonemap chain (D3); else `format=yuv420p` |
| Duration | `load(.duration)` → seconds | progress denominator (D6); 140 s cap is informational (account is Premium) |

Use the async AVFoundation load APIs (`load(_:)`, `loadTracks(withMediaType:)`) rather than the deprecated synchronous `asset.tracks`.

### D6 — Progress via `-progress pipe:1`

`ffmpeg` is run with `-progress pipe:1 -nostats`; it emits `key=value` blocks on stdout terminated by `progress=continue` / `progress=end`. We read `out_time_us` and divide by `duration_seconds * 1_000_000` to get a 0–1 fraction, published to the UI. stdout is read via the `Pipe` `readabilityHandler`; **stderr is captured separately** so its tail can be shown on failure (D-risks).

### D7 — App architecture & state machine

```
Xconvert.app
├─ XconvertApp (SwiftUI App) — single WindowGroup, .preferredColorScheme(.dark)
├─ ContentView — renders by Converter.phase; .dropDestination(for: URL.self)
│                + .fileImporter (allowedContentTypes: [.movie, .video, ...])
├─ Converter (@Observable model)
│    phase: .idle | .inspecting | .converting(Double) | .done(URL) | .error(String)
│    convert(url) async:
│      1. inspect(url)  → AVAsset reads (D5)
│      2. buildArgs()   → base chain + audio/HDR branches (D3/D4)
│      3. run ffmpeg    → Process(at: bundledFfmpegURL) + Pipes, stream progress (D6)
│      4. on success    → NSWorkspace.shared.activateFileViewerSelecting([out]); phase=.done
│      5. on failure    → phase=.error(stderrTail)
└─ Contents/Resources/ffmpeg — bundled static arm64 binary
```
`bundledFfmpegURL = Bundle.main.url(forResource: "ffmpeg", withExtension: nil)`. After any terminal state the user can drop/pick another file (resets to `.idle`).

### D8 — Always transcode (no smart skip in v1)

Even spec-compliant inputs are re-encoded. Detecting "already compliant" adds inspection complexity and risk for negligible benefit on short clips (transcode is ~1–2 s). A "smart skip / pass-through" can be added later if it becomes annoying.

### D9 — Packaging: bundled static `arm64` ffmpeg, sandbox off, ad-hoc signing

- **Bundle a static `arm64` `ffmpeg`** in *Copy Bundle Resources*. Homebrew's `ffmpeg` is dynamically linked and won't run relocated, so a static build (e.g. a GPL static `arm64` release) is required; it **must include libx264 and libzimg** (verify: `ffmpeg -hide_banner -filters | grep zscale` and `-encoders | grep libx264`). Ensure the executable bit survives into the bundle (build-phase `chmod +x`, or `chmod` at first run as a fallback).
- **App Sandbox OFF.** The app writes a sibling output file next to an arbitrary source and launches an embedded executable; the sandbox would block both, and turning it off avoids security-scoped bookmarks.
- **Hardened Runtime OFF for v1** + **ad-hoc signing**; clear Gatekeeper on first launch with right-click → Open. If notarization is ever wanted (to share the app), Hardened Runtime must go on and the embedded `ffmpeg` must be signed or granted the `com.apple.security.cs.disable-library-validation` entitlement — out of scope for v1.
- **Deployment target macOS 13 (Ventura)+** for `.dropDestination(for:)` and the async AVFoundation load APIs.

## Risks / Trade-offs

- **Static `ffmpeg` missing `libzimg`** → HDR tonemap (D3) fails. → Vendor a full GPL static build and verify `zscale`/`libx264` presence before bundling.
- **Executable bit lost in the bundle** → `Process` launch fails with a permissions error. → Add a build-phase `chmod +x`, and `chmod` at runtime if not executable.
- **HDR detection false negative** → washed-out colors. → Detect via the format description's transfer function (HLG / SMPTE-2084); when uncertain, fall back to the SDR path (no worse than the original validated behavior).
- **`anullsrc` + `-map` stream-mapping mistakes** → wrong/no audio. → Use explicit `-map 0:v:0 -map 1:a:0 -shortest`; this exact form was validated end-to-end.
- **Rotation / `preferredTransform`** → portrait phone clips mis-sized if `naturalSize` is used raw. → Always apply `preferredTransform` to get display dimensions (D5).
- **Deterministic output name overwrites** a previous `<name>-x.mp4`. → Acceptable for a personal tool; unique-naming is a possible later enhancement.
- **Gatekeeper friction** on first launch (unsigned/ad-hoc). → Documented right-click → Open; one-time.
- **Bundle size** grows by ~40–80 MB for the static `ffmpeg`. → Irrelevant for a personal Mac tool.

## Migration Plan

This is a new local app — no production deploy, no rollback beyond deleting the `.app`.

1. Create an Xcode SwiftUI macOS app target "Xconvert" (arm64, deployment target macOS 13+).
2. Vendor a static `arm64` `ffmpeg` (with `libx264` + `libzimg`); add to *Copy Bundle Resources`; ensure executable bit.
3. Disable App Sandbox; leave Hardened Runtime off; configure ad-hoc signing.
4. Implement `Converter` (inspect → buildArgs → run → progress → reveal) and `ContentView` (drop + picker + state machine, dark mode).
5. Build; first launch via right-click → Open.
6. **Acceptance check:** convert a real out-of-spec clip (e.g. a `120 fps` screen recording) and confirm the resulting `<name>-x.mp4` posts to X.

## Open Questions

- Which static `ffmpeg` build to vendor (must include `libx264` + `libzimg`); pin a specific version for reproducibility.
- Ship HDR tonemapping in v1, or start SDR-only and add it when a screen recording first comes out grey? (Leaning: include it, with the SDR fallback.)
- Deployment target — macOS 13 vs 14? (Leaning 13 / Ventura.)
