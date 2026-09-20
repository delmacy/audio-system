# Phase 17 — Live Player Branch / 17.0.0

## Purpose

Phase 17 introduces the live-playback branch for the Web Player without reading partial MXF files. Live playback is fed by an ingest-side branch/event stream and remains separate from historical MXF playback.

```text
Recorder ingest path
  RTP -> Media Engine -> MXF Writer
                 \
                  -> Live Tap -> Live Player Buffer -> Browser
```

## Non-goals

- Do not read `.mxf.partial` as the live source.
- Do not make the player responsible for evidence storage.
- Do not treat browser-buffered audio as evidentiary media.
- Do not reintroduce RX/TX split. One service remains one mono audio flow.

## Contract

The Live Player receives lightweight envelopes:

```json
{
  "schema": "recorder-poc.live-frame.v1",
  "service_id": "121500",
  "logical_track_uuid": "...",
  "media_flow": "mono",
  "rtp_timestamp": 123456,
  "sequence": 42,
  "payload_encoding": "pcma/8000/1",
  "frame_duration_ms": 20,
  "received_utc": "2026-09-19T13:00:00.020Z"
}
```

For Phase 17 the browser uses deterministic fixture frames to prove UI behavior. Production can replace the fixture with Server-Sent Events, WebSocket, WebRTC, or another low-latency transport without changing the evidence model.

## Latency target

Initial PoC target: approximately 1–2 seconds glass-to-glass for local lab conditions. The target is operational convenience, not evidence timing. Evidence timing remains in Recorder events, RTP timestamps, MXF files and the temporal index.

## Buffer policy

- The browser maintains a short rolling buffer.
- If the live branch stalls, the UI marks `LIVE_STALLED`.
- If the live branch resumes, the UI marks `LIVE_RECOVERED`.
- Historical playback remains the source for investigation and export.

## Relation to historical player

Historical playback:

```text
SQLite Temporal Index -> Historical Playback Plan -> Segment Export/Decode -> Web Player
```

Live playback:

```text
Recorder Live Tap -> Live Player Buffer -> Web Player
```

The two paths share service identity and timeline concepts, but their media sources are separate.
