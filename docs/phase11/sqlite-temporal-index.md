# Phase 11 — SQLite Temporal Index

The Recorder media path does not synchronously depend on SQLite. The Recorder emits media, manifests and append-only events. A separate Temporal Indexer batches those records into SQLite WAL.

Canonical lookup:

`LogicalTrackUUID + [from_utc, to_utc)`

returns ordered physical segments:

`FileId, TrackInstanceUUID, TrackIndex, valid_from_utc, valid_to_utc, relative_path`.

Rules:
- UTC internally.
- One mono media track per logical service.
- No fabricated silence for unknown intervals.
- Historical closed MXFs are immutable.
- Index can be rebuilt from MXF embedded identity, manifests and event logs.
- Database failure must not stop RTP ingest or MXF persistence.
- Ordering uses `recording_window_start_utc + segment_sequence`, not file creation time.
