# Phase 14 — Playback Decode / Segment Export

## Goal

Phase 14 turns the Phase 13 historical playback plan into a concrete export boundary.
It does **not** change the Recorder write path. It consumes index-derived playback plans and produces audio/export artifacts for player, investigation or operator review.

Canonical flow:

```text
LogicalTrackUUID + UTC interval
        ↓
Historical Playback Plan
        ↓
Segment Resolver
        ↓
MXF/TrackInstanceUUID decode boundary
        ↓
Export Bundle
```

## Core rule

Playback/export follows logical identity, not physical file layout:

```text
LogicalTrackUUID -> PlaybackPlan items -> FileId + TrackInstanceUUID + TrackIndex -> decoded audio segment
```

`TrackIndex` is file-local. `TrackInstanceUUID` proves which physical occurrence of the logical track is being decoded.

## Export modes

### `only_audio`

Concatenate only recorded media intervals. Absolute UTC timing is preserved in the manifest, not by inserting silence.

### `continuous`

Preserve the requested time span. Gap items are represented in the export manifest. If an audio container requires duration continuity, the exporter may insert generated silence only when the manifest marks it explicitly as:

```text
kind = synthetic_gap_silence
source = no_recorded_media_gap
not_evidence_audio = true
```

This is not treated as recorded media.

### `evidence_bundle`

Produce an audio file plus manifest, timeline events and source mapping. The manifest is the authoritative record for what was decoded and what was synthesized for presentation.

## Output bundle

```text
exports/<export-id>/
├── export.wav
├── export-manifest.json
├── playback-plan.json
├── source-map.csv
└── events.jsonl
```

The manifest records:

- query interval
- `LogicalTrackUUID`
- every source `FileId`
- physical MXF path
- `TrackInstanceUUID`
- file-local `TrackIndex`
- decoded interval
- sample rate/channel/codec
- gap policy
- synthetic silence sections, if any
- hashes when available

## Decode implementation boundary

The production decoder will use GStreamer/FFmpeg or a native demux boundary to extract the selected mono PCMA track from MXF. The extractor must select by `TrackInstanceUUID`/TrackName metadata when possible, with TrackIndex only as a resolved file-local fallback.

Phase 14 materializes the contract and a deterministic PowerShell harness. The harness can generate a small WAV from the plan for smoke validation without requiring real MXF media during construction.

## Non-goals

- No final browser player UI.
- No live streaming.
- No evidentiary certification.
- No assumption that gaps are recorded silence.
- No RX/TX split; service audio remains mono.
