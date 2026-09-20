# CHANGELOG — Phase 14 / 14.0.0

## Added

- Phase 14 Playback Decode / Segment Export contract.
- Export bundle shape: `export.wav`, `export-manifest.json`, `playback-plan.json`, `source-map.csv`, `events.jsonl`.
- Deterministic PowerShell export harness:
  - `scripts/playback/Invoke-PlaybackSegmentExport.ps1`
  - `scripts/playback/12-playback-segment-export-smoke.cmd`
- Playback export configuration:
  - `config/playback/segment-export.ini`
- Scenario fixture:
  - `scenarios/playback/segment-export-01.json`

## Design decisions

- Playback/export resolves media through `LogicalTrackUUID` and `TrackInstanceUUID` rather than filename or stable track index assumptions.
- Gaps remain explicit. `continuous` export may synthesize silence only as marked presentation material, never as recorded evidence.
- Mono service model remains preserved: one service equals one mono audio flow and one logical track.

## Deferred

- Production MXF demux/decode integration.
- HTTP streaming.
- Browser playback UI.
- Evidentiary export signing/hash chain.
