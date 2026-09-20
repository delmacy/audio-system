# Phase 13 — Historical Playback API / 13.0.0

Materialized the first playback-facing API contract over the SQLite temporal index.

Added:

- `docs/phase13/historical-playback-api.md`
- `docs/phase13/acceptance.md`
- `config/playback/historical-playback.ini`
- `scenarios/playback/historical-playback-01.json`
- `scripts/playback/Invoke-HistoricalPlaybackPlan.ps1`
- `scripts/playback/11-historical-playback-smoke.cmd`

Key contract:

`LogicalTrackUUID + UTC interval -> playback plan`

The plan resolves physical MXF files, TrackInstanceUUIDs, TrackIndex values, media intervals, and explicit gaps without relying on filenames or stable physical track indexes.
