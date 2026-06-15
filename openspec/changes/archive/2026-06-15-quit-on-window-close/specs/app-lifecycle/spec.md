## ADDED Requirements

### Requirement: Closing the window quits the app

The GUI app SHALL terminate its process when the last window is closed, rather
than remaining resident in the Dock and menu bar. This is implemented by an
`NSApplicationDelegate` returning `true` from
`applicationShouldTerminateAfterLastWindowClosed(_:)`.

#### Scenario: User closes the window with the red "x"

- **WHEN** the user clicks the window's red close button (or presses `Cmd+W`)
- **THEN** the application process terminates
- **AND** the app no longer appears in the Dock or menu bar

#### Scenario: User quits with Cmd+Q

- **WHEN** the user presses `Cmd+Q`
- **THEN** the application terminates as it does today (behavior unchanged)

#### Scenario: Headless mode is unaffected

- **WHEN** the app is launched with `--convert <path>` (no GUI window)
- **THEN** the window-close termination behavior does not apply, and the process
  exits when the headless conversion completes as it does today

### Requirement: Quitting cancels an in-flight conversion cleanly

When the app terminates while a conversion is running, it SHALL terminate the
bundled ffmpeg child process so no orphaned process outlives the app, and it
SHALL NOT leave a partial `<name>-x.mp4` presented as a completed output.

#### Scenario: Close window during an active conversion

- **WHEN** a conversion is in progress (`Converter.phase == .converting`) and the
  user closes the window
- **THEN** the running ffmpeg child process is terminated
- **AND** no ffmpeg process remains running after the app exits

#### Scenario: No completed conversion is misreported after cancellation

- **WHEN** a conversion is cancelled by quitting before ffmpeg finishes
- **THEN** the partial output file is not reported to the user as a finished,
  X-ready result
