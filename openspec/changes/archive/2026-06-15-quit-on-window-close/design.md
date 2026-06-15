## Context

Xconvert is a SwiftUI `App` with a single `WindowGroup` and no `App`/scene
delegate. It therefore inherits macOS's default lifecycle: closing the window
leaves the process resident (Dock + menu bar), terminating only on `Cmd+Q`. For
a one-window, no-document utility this is surprising — users expect "x" to quit.

Two existing facts shape the implementation:

1. The conversion runs as a detached `Task` in `Converter.run(url:)`, which calls
   `FFmpegRunner.run` — a static function that creates its `Process` internally
   and exposes **no handle**. There is currently no way to cancel a running
   conversion.
2. On macOS, when a parent process exits, its children are **not** killed — they
   are reparented to `launchd` and keep running. So simply letting the app quit
   would leave an **orphaned ffmpeg** chewing CPU with no UI. Clean teardown must
   explicitly terminate the child.

## Goals / Non-Goals

**Goals:**
- Closing the window (red "x" / `Cmd+W`) terminates the app process.
- Quitting (window-close or `Cmd+Q`) while converting terminates the bundled
  ffmpeg child cleanly — no orphan survives the app.
- A cancelled conversion is never reported to the user as a finished, X-ready
  output.
- Headless `--convert` mode keeps its current behavior (no GUI lifecycle).

**Non-Goals:**
- A "conversion in progress — quit anyway?" confirmation dialog (see Open
  Questions; v1 just cancels).
- Background/menu-bar (accessory) operation, or keeping conversions running after
  the window closes — that resident behavior is intentionally removed.
- Resumable/queued conversions, multi-window support.

## Decisions

### D1 — Quit via `NSApplicationDelegate`, not SwiftUI window-close detection
Wire an `AppDelegate: NSObject, NSApplicationDelegate` into `XconvertApp` with
`@NSApplicationDelegateAdaptor`, and return `true` from
`applicationShouldTerminateAfterLastWindowClosed(_:)`.

*Why:* this is the documented AppKit hook for exactly this behavior, one line of
intent, and robust. Alternatives rejected: detecting window close in SwiftUI
(`scenePhase`, `.onDisappear`, observing `NSWindow`) and calling
`NSApplication.shared.terminate(nil)` is hackier and fights the framework;
macOS 14's declarative scene APIs aren't available because we target macOS 13.

### D2 — The delegate reaches the live conversion through the shared `Converter`
Termination teardown needs access to the running conversion. `XconvertApp` owns
the `Converter` as `@StateObject`; the adaptor-created delegate is separate. Wire
them together: pass/assign the same `Converter` instance to the delegate (e.g.
the delegate holds a `weak var converter`, set when the scene builds, or the
`Converter` is exposed as a shared instance the delegate reads). The delegate's
teardown calls a new `Converter.terminateNow()`.

*Why:* keeps `Converter` the single owner of conversion state and the child
process; the delegate just signals it. Avoids duplicating process bookkeeping in
the delegate.

### D3 — Make the conversion cancellable; tear down synchronously on terminate
`FFmpegRunner.run` is extended so the running `Process` is reachable for
termination. Preferred shape: wrap the continuation in
`withTaskCancellationHandler` and call `process.terminate()` (SIGTERM) when the
`Task` is cancelled; `Converter` stores its conversion `Task` and
`terminateNow()` cancels it. Equivalent acceptable shape: hand the `Process` back
to `Converter` so it can `terminate()` directly.

Do the actual kill in `applicationWillTerminate(_:)` (or the synchronous portion
of `applicationShouldTerminate`): send SIGTERM via `process.terminate()` and
`waitUntilExit()` with a short bound so we don't exit before the child does.
ffmpeg handles SIGTERM promptly, so the wait is brief.

*Why:* `applicationWillTerminate` runs for both window-close-quit and `Cmd+Q`,
so a single teardown path covers every quit. A bounded synchronous wait is what
guarantees "no orphan survives the app" (D-context fact #2).

### D4 — A cancelled conversion never reports `.done`
On `process.terminate()`, ffmpeg exits non-zero, so `FFmpegRunner` resumes by
throwing (or the cancelled `Task` throws `CancellationError`); either way
`Converter.run` does not reach the `phase = .done(...)` / Finder-reveal line. No
extra guard is needed for correctness. Because we're quitting, surfacing an
error phase is moot. Deleting the partial `<name>-x.mp4` is optional cleanup
(see Open Questions) — `-faststart` means an interrupted file is incomplete
anyway and the next run overwrites it via `-y`.

### D5 — Headless mode untouched
`--convert` is dispatched in `XconvertEntry.main()` before `XconvertApp.main()`,
so it never instantiates `NSApplication` or the delegate. No change there.

## Risks / Trade-offs

- **Orphaned ffmpeg if teardown isn't synchronous** → terminate + bounded
  `waitUntilExit()` in `applicationWillTerminate`; do not rely on the OS to reap
  the child (it won't).
- **Losing the accidental "keep converting after close" behavior** → intentional
  per the proposal; a user who wants the result must leave the window open. If
  this proves annoying, the confirm-dialog (Open Questions) is the escape hatch,
  not resident operation.
- **Concurrency correctness** → `Converter` is `@MainActor`; the delegate hooks
  run on the main thread, so calling `terminateNow()` is main-actor-safe.
  `Process.terminate()`/`waitUntilExit()` are safe to call cross-thread on the
  retained process. Keep the existing `ProcessOutputCollector` locking intact.

## Open Questions

- **Confirm before quitting mid-conversion?** v1 cancels silently. A
  `applicationShouldTerminate` returning `.terminateLater` + an alert ("A
  conversion is in progress. Quit anyway?") is a possible follow-up if silent
  cancellation feels abrupt.
- **Delete the partial output on cancel?** Leaning no (next `-y` run overwrites,
  and it's never reported as done), but removing it would avoid leaving a broken
  `<name>-x.mp4` in the user's folder.
