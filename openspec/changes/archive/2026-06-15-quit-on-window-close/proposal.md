## Why

Xconvert is a single-window, single-purpose utility, but it inherits macOS's
default app-lifecycle behavior: closing the window with the red "x" only closes
the window — the process stays resident (still in the Dock and menu bar). Users
expect "x" to mean "I'm done" for a one-window tool, and a lingering background
process is surprising for an app with no document model and nothing to keep
alive. This change makes the app quit when its window is closed.

## What Changes

- Closing the last window (red "x" / `Cmd+W`) now **terminates the app**, instead
  of leaving it resident in the Dock and menu bar.
- An `NSApplicationDelegate` is wired into the SwiftUI app via
  `@NSApplicationDelegateAdaptor`; it returns `true` from
  `applicationShouldTerminateAfterLastWindowClosed`.
- An **in-flight conversion is cancelled cleanly on quit**: the bundled ffmpeg
  child process is terminated so no orphaned process survives the app, and no
  partial `<name>-x.mp4` is left presented as a finished output.
- Headless `--convert` mode is unaffected (it has no window and never starts the
  GUI app lifecycle).

## Capabilities

### New Capabilities
- `app-lifecycle`: How the application starts, stays resident, and terminates —
  specifically that closing the window quits the app, and that quitting tears
  down any running conversion (child ffmpeg process) cleanly.

### Modified Capabilities
<!-- None. The conversion contract and converter-ui drop/convert behavior are unchanged. -->

## Impact

- **Code**: `Sources/Xconvert/App.swift` (add `NSApplicationDelegateAdaptor` +
  delegate). Conversion-teardown touches `Converter` (expose a cancel) and
  `FFmpeg.swift` `FFmpegRunner` (terminate the `Process`); both already manage
  the child process, so this is a cancel hook, not new infrastructure.
- **No change** to the conversion contract, the ffmpeg command/branches, the drop
  UI, or distribution/signing (still sandbox-off, ad-hoc signed).
- **Behavioral**: the previously-accidental "conversion keeps running after the
  window closes" is intentionally removed in favor of clean termination.
