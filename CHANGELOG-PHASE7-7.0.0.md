# Phase 7 — 7.0.0 — Window Rotation real

Phase 7 materializes logical recording-window rotation inside `recorder-host.exe`.

## Added

- Recorder-owned window rotation at a safe `PAUSE` boundary.
- `--rotate-window-after-pauses N` and `--rotate-window-max-count N` host options.
- Persistent RTSP Session continuity across physical MXF rollover.
- Stable `LogicalTrackUUID` across windows.
- Renewed `TrackInstanceUUID`, `FileId`, `.mxf.partial`, `.mxf`, `.lock`, `StorageWriter` and `mxfidmux` pipeline for the new physical window.
- Window lifecycle audit events:
  - `WINDOW_ROTATION_REQUESTED`
  - `WINDOW_CLOSING`
  - `WINDOW_CLOSED_COMPLETE`
  - `WINDOW_OPENED`
  - `WINDOW_ROTATED`
- Additional summary counters:
  - `window_open_count`
  - `windows_closed_complete`
  - `rotations_completed`
  - `segment_sequence`
- Future integrated gate:
  - `scripts\recorder\06-window-rotation-smoke.cmd`
- Scenario config:
  - `config\recorder\window-rotation.ini`

## Contract

`PAUSE` closes an activity interval. When the rotation threshold is reached, the Recorder finalizes the current MXF window and opens the next one without tearing down the RTSP session or changing the `LogicalTrackUUID`.

`TEARDOWN` remains the service/session disable operation and finalizes the currently open window.

## Scope note

This phase is materialized for the later integrated target campaign. It is not marked target-validated until compiled and executed on the Windows/GStreamer environment.
