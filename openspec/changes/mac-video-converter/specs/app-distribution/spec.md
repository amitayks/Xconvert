## ADDED Requirements

### Requirement: Self-contained ffmpeg

The app SHALL bundle a static `arm64` `ffmpeg` binary inside its app bundle (`Contents/Resources/ffmpeg`) and use that binary for all transcoding. The app SHALL NOT require Homebrew, a system-installed `ffmpeg`, or any other external dependency to perform a conversion.

#### Scenario: Works without any installed ffmpeg

- **WHEN** the app runs on a Mac that has no `ffmpeg` installed anywhere on the system
- **THEN** conversions still succeed using the bundled binary

### Requirement: Fully offline operation

The app SHALL perform all of its work locally with no network access. It SHALL NOT make API calls, send telemetry, or require connectivity.

#### Scenario: Conversion with networking disabled

- **WHEN** the Mac has networking disabled
- **THEN** the app still inspects and converts videos normally

### Requirement: Write sibling output and run embedded binary

The app SHALL be configured so it can write the `<name>-x.mp4` output into the same directory as the source file and can launch the embedded `ffmpeg` binary. (This requires the macOS App Sandbox to be disabled for the app.)

#### Scenario: Sibling file written next to an arbitrary source

- **WHEN** the user converts a file located in an arbitrary folder (e.g. `~/Downloads`)
- **THEN** the app writes `<name>-x.mp4` into that same folder without a sandbox permission error

### Requirement: Personal distribution and first-launch

The app SHALL be runnable on the user's own Mac using personal / ad-hoc code signing, with first launch performed via right-click → Open to clear Gatekeeper. Apple notarization SHALL NOT be required for personal use; it is only needed to distribute the app to other people (out of scope for v1).

#### Scenario: First launch on the user's Mac

- **WHEN** the user opens the freshly built app for the first time via right-click → Open
- **THEN** the app launches and is usable
- **AND** subsequent launches open normally without the Gatekeeper prompt

### Requirement: Apple-silicon target

The app and its bundled `ffmpeg` SHALL run natively on Apple-silicon (`arm64`) Macs.

#### Scenario: Runs on Apple silicon

- **WHEN** the app is launched on an Apple-silicon Mac
- **THEN** both the app and the bundled `ffmpeg` execute natively as `arm64`
