## Why

X (Twitter) silently rejects a tweet's video with `400 "Your media IDs are invalid"` when the source file is outside X's tweet-video spec: the chunked media upload reports success, but `POST /2/tweets` refuses the out-of-spec media. The confirmed trigger is **Mac screen recordings at native ProMotion resolution/fps** (e.g. `3024×1964 @ 120 fps`). X caps tweet video at **≤1920×1200, ≤60 fps, H.264 + AAC, ≤140 s**. A spec-compliant transcode of the same clip (≤1280 wide, 30 fps, H.264 High, AAC, `yuv420p`, `+faststart`) posts immediately.

There is no good *automatic* fix for this particular setup: a server-side transcode needs Cloudflare's paid plan, and in-browser `ffmpeg.wasm` is too slow/unreliable for 6-megapixel 120 fps clips. Native `ffmpeg` on the Mac does the same job in ~1–2 s. So the pragmatic fix is a **small, fully-local macOS app**: drop a video, get back an X-ready MP4. This is a personal convenience tool — no network, no API, no dependency on any posting service.

## What Changes

- **New standalone macOS app (Xconvert).** A SwiftUI, dark-mode, single-window app whose whole job is: accept a video → produce an X-spec MP4.
- **Drag-and-drop + file picker input.** Drop a video file onto the window (or pick one); any common container is accepted (`.mov`, `.mp4`, `.m4v`, `.mkv`, `.webm`, `.avi`, …) since `ffmpeg` decodes them all.
- **Hybrid inspect/transcode engine.** Inspection is native **AVFoundation** (duration, dimensions, frame rate, audio-track presence, color transfer / HDR). The transcode runs a **bundled static `arm64` `ffmpeg`** binary via `Process`, using the validated X-spec command.
- **Two inspection-driven branches.** (1) Source has **no audio track** → inject a silent AAC track (`anullsrc`) so X accepts it. (2) Source is **HDR** (HLG/PQ transfer) → tonemap to SDR before `format=yuv420p` so colors aren't washed out.
- **Longest-edge scaling.** Scale caps the **longest** edge to ≤1280, preserving aspect, so both landscape and portrait clips stay within X's dimension limits.
- **Output + feedback.** Writes `<name>-x.mp4` next to the original and reveals it in Finder. The window shows a clear state machine: idle → inspecting → converting (with progress) → done / error.
- **Self-contained & offline.** The bundled `ffmpeg` means no Homebrew install; the app runs with no network access. App Sandbox is off (it writes a sibling file and launches an embedded binary); distribution is ad-hoc signed (right-click → Open clears Gatekeeper).

## Capabilities

### New Capabilities
- `video-conversion`: Given any common video file, inspect it with AVFoundation, derive the correct `ffmpeg` arguments (longest-edge scale, 30 fps cap, audio-injection and HDR-tonemap branches), run the bundled `ffmpeg`, and produce an X-tweet-video-spec MP4 (`<name>-x.mp4`) that is guaranteed to satisfy the spec.
- `converter-ui`: The SwiftUI dark-mode app shell — drag-and-drop and file-picker input, the idle/inspecting/converting/done/error state machine, conversion progress, reveal-in-Finder on success, and clear, actionable error messages.
- `app-distribution`: The app is fully self-contained and offline — a bundled static `arm64` `ffmpeg`, no external dependencies (no Homebrew), App Sandbox disabled to allow sibling-file output and embedded-binary execution, and a personal/ad-hoc signing + Gatekeeper-bypass story (notarization optional, only needed to share with others).

### Modified Capabilities
<!-- None. Xconvert is a brand-new project; openspec/specs/ is empty. -->

## Impact

- **New Xcode project** at `/Users/amkeisar/Keisar/Projects/Xconvert` (SwiftUI macOS app, `arm64`, dark mode). No existing code is modified.
- **New bundled binary:** a static `arm64` `ffmpeg` (~40 MB) at `Contents/Resources/ffmpeg`, kept executable inside the `.app`. (Homebrew's `ffmpeg` is dynamically linked and won't work bundled — a static build is required.)
- **System frameworks:** AVFoundation / AppKit (`NSWorkspace` for reveal-in-Finder), Foundation `Process`/`Pipe` for running `ffmpeg` and parsing `-progress pipe:1`.
- **No network, no API, no MusePostBot/Worker/webapp dependency.** Fully offline.
- **Distribution:** ad-hoc / personal code signing; first launch via right-click → Open to clear Gatekeeper. Notarization (Apple Developer account, $99/yr) is out of scope for v1 and only needed to distribute to other people.
- **Out of scope for v1:** batch / folder conversion, a Finder Quick Action / Services entry, copy-output-path-to-clipboard, and "smart skip if already in spec." These are noted as future enhancements.
