# Phase 19 — Integrity / Manifest Chain

## Goal

Phase 19 connects the evidential artifacts produced by the recorder, indexer, playback planner and export pipeline into one verifiable manifest chain.

The chain is:

```text
closed MXF
  -> recording-file-manifest.json
  -> SQLite temporal index rows
  -> historical playback plan
  -> segment export manifest
  -> evidence bundle manifest
  -> integrity verification report
```

## Contract

Every closed recording file must be represented by a manifest containing at least:

- `file_id`
- `recorder_id`
- `logical_track_uuid`
- `track_instance_uuid`
- `track_index`
- `recording_window_start_utc`
- `recording_window_end_utc`
- `segment_sequence`
- `media_flow = mono`
- `mxf_path`
- `mxf_sha256`
- `manifest_sha256`

The SQLite index must not become the sole source of truth. It is a query accelerator and can be rebuilt from MXF files, file manifests and event logs.

## Verification rules

A verification pass must confirm:

1. Every `source-map.csv` row references an existing `FileId`.
2. Every referenced `FileId` has a recording-file manifest.
3. Every source MXF hash matches the hash recorded in the manifest.
4. `LogicalTrackUUID` stays stable across file boundaries.
5. `TrackInstanceUUID` is physical-file scoped and must differ when a new physical file is created.
6. `TrackIndex` is file-local and must not be treated as an application identity.
7. Gap records are explicit and must not be converted into evidence audio.
8. The evidence bundle hash is calculated after all constituent files are written.

## Non-goals

Phase 19 does not implement legal digital signatures or external timestamp authorities. It prepares a deterministic manifest/hash chain suitable for a later signing/notarization layer.
