# Phase 13 — Historical Playback API

## Goal

Provide the first playback-facing boundary over the SQLite temporal index without coupling the Web Player to MXF filenames, Recorder internals, or physical track positions.

The canonical lookup is:

```text
LogicalTrackUUID + UTC interval -> ordered playback plan
```

A playback plan resolves:

- `FileId`
- physical MXF path
- `TrackInstanceUUID`
- file-local `TrackIndex`
- `RecordingWindowStartUTC`
- `SegmentSequence`
- media interval ranges
- explicit gaps
- timeline events such as SQU/PTT/RING/ANSWER/RELEASE/GAP/TOPOLOGY

## Non-goals

Phase 13 does not implement the final web UI, waveform rendering, live playback, or browser streaming. It defines and materializes the historical query contract and a PowerShell harness that can be replaced by an HTTP service later.

## Principles

1. The player never searches by filename.
2. The player never assumes stable TrackIndex across MXF files.
3. The player follows `LogicalTrackUUID` across windows.
4. Every physical file segment uses its own `TrackInstanceUUID`.
5. Gaps are explicit plan items, not fabricated silence.
6. All internal timestamps are UTC.
7. Ordering is `RecordingWindowStartUTC + SegmentSequence`, not physical creation time.
8. A missing interval is returned as a `gap` item unless evidence proves playable media.

## API shape

### Request

```json
{
  "logical_track_uuid": "7581bb95-...",
  "from_utc": "2026-09-19T13:00:00.000Z",
  "to_utc": "2026-09-19T13:10:00.000Z",
  "mode": "continuous",
  "include_events": true
}
```

### Response

```json
{
  "schema": "recorder-poc.historical-playback-plan.v1",
  "logical_track_uuid": "7581bb95-...",
  "from_utc": "2026-09-19T13:00:00.000Z",
  "to_utc": "2026-09-19T13:10:00.000Z",
  "items": [
    {
      "kind": "media",
      "file_id": "file-a",
      "path": "recordings/.../part000.mxf",
      "track_instance_uuid": "ti-a",
      "track_index": 4,
      "valid_from_utc": "2026-09-19T13:00:00.000Z",
      "valid_to_utc": "2026-09-19T13:03:12.000Z"
    },
    {
      "kind": "gap",
      "reason": "no_recorded_media",
      "from_utc": "2026-09-19T13:03:12.000Z",
      "to_utc": "2026-09-19T13:04:00.000Z"
    }
  ],
  "events": []
}
```

## Playback modes

### continuous

Return media and explicit gaps over the complete requested interval.

### only_audio

Return only media intervals, preserving their absolute UTC positions. The UI may jump visually between items, but the API does not rewrite time.

### event_overlay

Return media/gaps plus signaling and integrity events for the interval.

## Future HTTP endpoints

```text
GET /api/playback/services
GET /api/playback/plan?lt=<uuid>&from=<utc>&to=<utc>&mode=continuous
GET /api/playback/events?lt=<uuid>&from=<utc>&to=<utc>
GET /api/playback/media-segment?file_id=<id>&track_instance_uuid=<uuid>&from=<utc>&to=<utc>
```

Phase 13 materializes the plan builder first; decoding and streaming are later phases.
