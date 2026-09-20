# Phase 18 — Export Evidence Bundle

Phase 18 defines the evidential export package produced from a historical playback/export plan.

The export bundle is not just an audio file. It is a sealed investigation package containing:

- decoded audio segment(s), normally mono WAV 8 kHz for the PoC;
- export manifest with request parameters, service identity and time range;
- source map linking each exported interval to FileId, LogicalTrackUUID, TrackInstanceUUID, TrackIndex and physical MXF path;
- timeline events overlapping the exported interval;
- gap records, explicitly marked as no recorded media;
- hashes for exported audio, manifest, source map, event stream and package-level hash;
- chain-of-custody note for who/what created the export in the PoC context.

## Frozen rules

1. One service remains one mono audio flow.
2. Synthetic silence inserted for presentation is never evidence audio.
3. Gaps are explicit records.
4. Export must preserve the distinction between recorded media and presentation padding.
5. Export evidence is derived from closed MXF + Temporal Index + playback plan.
6. Live preview buffer is not an evidence source.

## Bundle shape

```text
export-bundle/
├── audio/
│   └── export.wav
├── manifest/
│   ├── export-manifest.json
│   ├── source-map.csv
│   ├── timeline-events.jsonl
│   └── gaps.jsonl
├── hashes/
│   ├── file-hashes.sha256
│   └── package-hash.txt
└── README-EVIDENCE.txt
```

## Evidence manifest fields

- `export_id`
- `created_utc`
- `mode`
- `logical_track_uuid`
- `service_id`
- `media_flow = mono`
- `interval_start_utc`
- `interval_end_utc`
- `source_files[]`
- `track_instances[]`
- `contains_synthetic_silence`
- `synthetic_silence_is_evidence = false`
- `hashes`

## Acceptance

The Phase 18 smoke creates a deterministic bundle from a sample playback plan and verifies:

- manifest exists;
- source map exists;
- timeline events are preserved;
- gaps remain explicit;
- hashes exist and match;
- package hash is deterministic for unchanged contents;
- the bundle contains no RX/TX split in the base service model.
