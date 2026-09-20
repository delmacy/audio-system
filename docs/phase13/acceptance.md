# Phase 13 Acceptance — Historical Playback API

The phase is accepted when a synthetic SQLite temporal index can produce a playback plan that:

- resolves one `LogicalTrackUUID` across at least two physical files;
- returns distinct `TrackInstanceUUID` values per file;
- orders files by `RecordingWindowStartUTC + SegmentSequence`;
- includes explicit `gap` items for unrecorded intervals;
- overlays signaling events without converting them into media;
- does not depend on MXF filename ordering;
- does not require the Recorder to be running;
- remains valid if `TrackIndex` changes between files.

Future integrated validation must additionally prove that the returned MXF/track items can be decoded and streamed.
