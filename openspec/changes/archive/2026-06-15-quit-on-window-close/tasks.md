## 1. Quit on last window close

- [x] 1.1 Add an `AppDelegate: NSObject, NSApplicationDelegate` in `App.swift` that returns `true` from `applicationShouldTerminateAfterLastWindowClosed(_:)`.
- [x] 1.2 Wire it into `XconvertApp` with `@NSApplicationDelegateAdaptor`.
- [x] 1.3 Build (`swift build`) and confirm the GUI launches unchanged.

## 2. Make a running conversion cancellable

- [x] 2.1 Extend `FFmpegRunner.run` so the spawned `Process` can be terminated (wrap the continuation in `withTaskCancellationHandler` calling `process.terminate()`, or hand the `Process` back to the caller).
- [x] 2.2 In `Converter`, store the conversion `Task` and add `@MainActor func terminateNow()` that cancels it / terminates the child process.
- [x] 2.3 Confirm a cancelled conversion does NOT reach `phase = .done(...)` / the Finder reveal (it throws instead).

## 3. Tear down the child process on quit

- [x] 3.1 Give `AppDelegate` access to the shared `Converter` instance (weak reference set when the scene builds, or a shared instance).
- [x] 3.2 In `applicationWillTerminate(_:)`, call `Converter.terminateNow()` and bound-wait (`waitUntilExit`) so the ffmpeg child exits before the app does — no orphan.
- [x] 3.3 Verify the same teardown path covers both window-close-quit and `Cmd+Q`.

## 4. Verify

- [x] 4.1 Launch `build/Xconvert.app`, close the window with "x" → confirm the process is gone (not in Dock/menu bar; `pgrep Xconvert` empty). *(Verified manually by user; automated GUI driving blocked by missing Accessibility permission. Monitor confirmed the app stays resident with no interaction, so it quits only on window close.)*
- [x] 4.2 Start a conversion, close the window mid-convert → confirm `pgrep ffmpeg` shows no orphaned process and no completed-output is reported. *(Verified manually by user.)*
- [x] 4.3 Confirm headless `--convert <path>` still converts and exits normally (lifecycle change does not apply).
- [x] 4.4 Sanity-check a normal full conversion still completes and reveals `<name>-x.mp4` in Finder (no regression).
