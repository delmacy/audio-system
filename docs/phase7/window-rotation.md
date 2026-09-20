# Phase 7 — Window Rotation

Phase 7 introduces physical-window rotation under one persistent service session.

## Core invariant

A recording window is a physical persistence boundary, not a session boundary.

Therefore:

- `PAUSE` may close a media interval and trigger window rollover.
- `TEARDOWN` disables/finalizes the session/service.
- `LogicalTrackUUID` remains stable across the rotated files.
- `TrackInstanceUUID` changes for each physical MXF occurrence.

## Rotation sequence

```text
PAUSE received after configured threshold
  -> MEDIA_END if active
  -> WINDOW_ROTATION_REQUESTED
  -> EOS current appsrc/mux
  -> Flush/promote current .mxf.partial to .mxf
  -> WINDOW_CLOSED_COMPLETE
  -> create new FileId / TrackInstanceUUID / paths
  -> open new StorageWriter
  -> rebuild mxfidmux pipeline with same LogicalTrackUUID and new TrackInstanceUUID
  -> WINDOW_OPENED
  -> WINDOW_ROTATED
  -> same RTSP Session accepts next RECORD
```

## Deferred smoke

`scripts\recorder\06-window-rotation-smoke.cmd` runs one radio session with four bursts and a rotation after the second `PAUSE`. Expected outcome:

- one `SESSION_OPEN` and one `SESSION_CLOSE`;
- one `WINDOW_ROTATED`;
- two closed MXF files;
- four media intervals;
- one stable `LogicalTrackUUID`;
- distinct `TrackInstanceUUID` values per segment.
