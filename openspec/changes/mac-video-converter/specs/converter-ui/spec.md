## ADDED Requirements

### Requirement: Accept a video via drag-and-drop

The app SHALL accept a video file dropped anywhere onto its main window and begin converting it. The drop zone SHALL give visual feedback while a draggable file is hovered over it. If multiple files are dropped at once, the app SHALL convert the first and ignore the rest (batch conversion is out of scope for v1).

#### Scenario: Drop a single video

- **WHEN** the user drags a video file onto the window and releases it
- **THEN** the app begins inspecting and converting that file

#### Scenario: Hover feedback

- **WHEN** a draggable file is hovered over the drop zone
- **THEN** the drop zone changes appearance to indicate it will accept the drop

#### Scenario: Multiple files dropped

- **WHEN** the user drops several files at once
- **THEN** the app converts the first file and ignores the others

### Requirement: Accept a video via file picker

The app SHALL provide a control to open a standard macOS open-file dialog filtered to video files, and convert the chosen file.

#### Scenario: Pick a file

- **WHEN** the user activates the "choose file" control and selects a video
- **THEN** the app begins inspecting and converting that file

### Requirement: Dark-mode appearance

The app SHALL present a dark-themed interface with legible contrast for its drop zone, status text, and progress.

#### Scenario: Dark UI rendered

- **WHEN** the app window is shown
- **THEN** it renders with a dark background and legibly-contrasted foreground elements

### Requirement: Reflect conversion state

The app SHALL communicate its current state to the user across the lifecycle: idle (ready for a file), inspecting, converting, done, and error. Each state SHALL be visually distinct.

#### Scenario: Idle state

- **WHEN** no conversion is in progress and none has just finished
- **THEN** the app shows an idle drop-zone prompt inviting the user to drop or choose a video

#### Scenario: Transition through states

- **WHEN** a file is accepted
- **THEN** the app shows an inspecting indicator, then a converting indicator, then a done (or error) state

### Requirement: Show conversion progress

While converting, the app SHALL show a determinate progress indicator that advances from 0% to 100%, derived from `ffmpeg`'s reported `out_time` relative to the source duration.

#### Scenario: Progress advances

- **WHEN** a conversion is running
- **THEN** the app shows a progress indicator that increases toward 100% as the conversion proceeds

### Requirement: Reveal output on success

On successful conversion, the app SHALL show a success state identifying the output file and SHALL reveal `<name>-x.mp4` in Finder.

#### Scenario: Output revealed in Finder

- **WHEN** a conversion completes successfully
- **THEN** the app shows a success state with the output file name
- **AND** reveals the `<name>-x.mp4` file selected in Finder

### Requirement: Report errors clearly

When a file is unsupported or a conversion fails, the app SHALL display a clear, human-readable message describing what went wrong, and SHALL return to a state from which the user can try another file.

#### Scenario: Unsupported file message

- **WHEN** the user provides a non-video / undecodable file
- **THEN** the app shows a message that the file is not a supported video

#### Scenario: Conversion failure message

- **WHEN** the conversion fails (e.g. `ffmpeg` exits non-zero)
- **THEN** the app shows a failure message and allows the user to try another file

### Requirement: Convert another file without restarting

After a conversion finishes (success or error), the app SHALL allow the user to convert another file by dropping or choosing it, without relaunching the app.

#### Scenario: Convert again after success

- **WHEN** a conversion has finished and the user drops a new video
- **THEN** the app converts the new file
