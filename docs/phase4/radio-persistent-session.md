# Phase 4 — Radio Persistent RTSP Session

## Goal

Turn the Phase 3 one-CWP vertical slice into the radio lifecycle used by the recorder PoC:

`service enabled -> ANNOUNCE -> SETUP -> READY -> (RECORD -> PAUSE)* -> TEARDOWN -> CLOSED`

An enabled frequency/service owns one persistent RTSP session and one open file writer for the current recording window. Silence is not a session teardown.

## State semantics

- `SETUP` enables the radio service and establishes the RTSP Session ID.
- `RECORD` opens the media gate on the existing session.
- the first accepted RTP packet after `RECORD` starts one media interval.
- `PAUSE` closes the media interval and media gate, but keeps RTSP, the MXF pipeline, and the `.mxf.partial` writer open.
- `GET_PARAMETER` is counted as liveness evidence. Successful keepalives are aggregated instead of generating one human audit line per request.
- the next `RECORD` reuses the same Session ID, LogicalTrackUUID, TrackInstanceUUID and physical MXF file.
- `TEARDOWN` represents radio service/frequency disable and triggers finalization.

## Radio activity metadata

Phase 4 adds an explicit PoC activity mapping selected by `--activity-signal`:

- `squ`: emit `SQU_ON/SQU_OFF` around each RECORD/PAUSE activity interval.
- `ptt`: emit `PTT_ON/PTT_OFF`.
- `none`: no activity-signal event.

This is a PoC semantic mapping for the simulator. It is not a claim about the exact attribute/header used by a target ED-137 profile; target-specific signaling remains subject to profile verification.

## Negative media gate proof

The persistent-session simulator deliberately sends RTP while the session is PAUSED. Those packets must:

1. arrive at the Recorder UDP socket;
2. increment `packets_received`;
3. increment `packets_ignored_not_recording`;
4. not be pushed to appsrc/MXF;
5. not create a MEDIA_START interval.

This distinguishes open signaling/session state from active recorded media.

## Counters

Recorder summary adds:

- `record_commands`
- `pause_commands`
- `keepalives`
- `media_intervals_started`
- `media_intervals_closed`
- `packets_ignored_not_recording`
- `teardown`

The original Phase 3 summary prefix is preserved for backward compatibility.

## Deferred validation

The command `scripts/recorder/03-radio-persistent-session-smoke.cmd` is materialized but intentionally deferred to integrated system acceptance. Phase 4 implementation is not marked target-validated until that campaign is run on the Windows/GStreamer target.
