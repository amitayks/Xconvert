## ADDED Requirements

### Requirement: Accept common video containers as input

The system SHALL accept a single local video file in any common container that `ffmpeg` can decode (including `.mov`, `.mp4`, `.m4v`, `.mkv`, `.webm`, `.avi`). The system SHALL reject files that are not decodable video and report a clear error rather than producing an invalid output.

#### Scenario: Decodable video accepted

- **WHEN** the user provides a `.mov` screen recording
- **THEN** the system proceeds to inspect and convert it

#### Scenario: Non-video file rejected

- **WHEN** the user provides a file that is not a decodable video (e.g. a `.pdf` or a corrupt file)
- **THEN** the system does not attempt a transcode and reports an "unsupported / not a video file" error

### Requirement: Inspect source metadata with AVFoundation

Before transcoding, the system SHALL read the source's duration, pixel dimensions, nominal frame rate, presence of an audio track, and color transfer characteristics using AVFoundation (AVAsset). The system SHALL NOT depend on `ffprobe` or any external metadata tool.

#### Scenario: Metadata drives the conversion plan

- **WHEN** a video is accepted
- **THEN** the system reads its duration, width×height, frame rate, audio-track presence, and color transfer
- **AND** uses those values to select the transcode arguments and to compute conversion progress

### Requirement: Produce X-tweet-video-spec output

The system SHALL produce an MP4 whose video stream is H.264 (High profile), whose audio stream is AAC, with pixel format `yuv420p` and `+faststart`, such that the output satisfies X's tweet-video spec and is accepted by `POST /2/tweets`.

#### Scenario: Out-of-spec source becomes postable

- **WHEN** a `3024×1964 @ 120 fps` screen recording is converted
- **THEN** the output is H.264 High + AAC, `yuv420p`, `+faststart`, ≤1280 on its longest edge, ≤30 fps
- **AND** the output is within X's tweet-video spec

### Requirement: Cap frame rate at 30 fps

The output frame rate SHALL NOT exceed 30 fps. Sources already at or below 30 fps SHALL NOT be increased beyond their value in a way that exceeds 30 fps.

#### Scenario: High-fps source is downsampled

- **WHEN** the source is 120 fps
- **THEN** the output is 30 fps

#### Scenario: Low-fps source stays within cap

- **WHEN** the source is 24 fps
- **THEN** the output frame rate does not exceed 30 fps

### Requirement: Scale by longest edge preserving aspect ratio

The system SHALL cap the source's **longest** edge to ≤1280 pixels, preserving the original aspect ratio and keeping both output dimensions even. Sources whose longest edge is already ≤1280 SHALL keep their original dimensions. This SHALL apply correctly to both landscape and portrait videos so neither exceeds X's dimension limits.

#### Scenario: Large landscape clip scaled down

- **WHEN** the source is `3024×1964` (landscape)
- **THEN** the output width is 1280 and the height is scaled proportionally to an even number

#### Scenario: Portrait clip respects the longest-edge cap

- **WHEN** the source is `1080×1920` (portrait)
- **THEN** the output's longest edge (height) is ≤1280 with width scaled proportionally
- **AND** the aspect ratio is preserved

#### Scenario: Already-small clip not upscaled

- **WHEN** the source is `640×360`
- **THEN** the output keeps `640×360`

### Requirement: Inject a silent audio track when the source has none

When the source has no audio track, the system SHALL inject a silent AAC stereo track (44.1 kHz) matched to the video length, because X requires an audio track on tweet video. When the source has an audio track, the system SHALL transcode it to AAC.

#### Scenario: Silent video gets a silent track

- **WHEN** the source has no audio track
- **THEN** the output contains a silent AAC stereo track for the full duration of the video

#### Scenario: Source audio is preserved

- **WHEN** the source has an audio track
- **THEN** the output contains an AAC audio track derived from the source audio

### Requirement: Tonemap HDR sources to SDR

When the source's color transfer is HDR (HLG or PQ), the system SHALL tonemap it to SDR (BT.709) before producing the `yuv420p` output, so colors are not washed out or darkened. SDR sources SHALL be converted to `yuv420p` without tonemapping.

#### Scenario: HDR screen recording tonemapped

- **WHEN** the source's color transfer is HLG or PQ (HDR)
- **THEN** the output is tonemapped to SDR (BT.709) `yuv420p` with natural-looking colors

#### Scenario: SDR source converted directly

- **WHEN** the source is already SDR
- **THEN** the output is `yuv420p` with no tonemapping applied

### Requirement: Write output next to the original

On success, the system SHALL write the converted file into the same directory as the source, named `<original-basename>-x.mp4`, overwriting any existing file of that name. The system SHALL NOT modify or delete the original source file.

#### Scenario: Output written as sibling file

- **WHEN** the source is `~/Downloads/TFS-video.mov`
- **THEN** the output is written to `~/Downloads/TFS-video-x.mp4`
- **AND** the original `~/Downloads/TFS-video.mov` is unchanged

### Requirement: Preserve source duration

The system SHALL NOT trim the source; the output duration SHALL match the source duration. Durations beyond X's non-Premium 140 s limit SHALL still be converted in full (treated as informational, since the user account is X Premium).

#### Scenario: Long video converted in full

- **WHEN** the source is 3 minutes long
- **THEN** the full 3-minute clip is converted with no trimming

### Requirement: Detect and report transcode failure

When the bundled `ffmpeg` process exits with a non-zero status, the system SHALL treat the conversion as failed, SHALL NOT present a partial output as success, and SHALL surface a diagnostic that includes the tail of `ffmpeg`'s error output.

#### Scenario: ffmpeg failure surfaced

- **WHEN** `ffmpeg` exits non-zero during conversion
- **THEN** the system reports a conversion failure including the tail of the `ffmpeg` error output
- **AND** does not report success
