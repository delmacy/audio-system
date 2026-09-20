# Phase 11 — 11.0.0

- Added SQLite WAL temporal-index schema.
- Added logical-track, file, track-instance, media-interval, event and checkpoint tables.
- Added canonical LogicalTrackUUID + interval query.
- Preserved asynchronous indexing boundary: Recorder does not depend on database availability.
- Added Phase 11 documentation, configuration and future smoke gate.
