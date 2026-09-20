# Phase 4 — 4.0.0

## Radio persistent RTSP session

- formalizes enabled-radio lifetime as one persistent RTSP session;
- validates Session header on post-SETUP methods;
- RECORD/PAUSE are idempotent state transitions on the same session;
- counts successful GET_PARAMETER keepalives without per-keepalive human log spam;
- adds aggregate KEEPALIVE_OK evidence at session close;
- adds SERVICE_ENABLED/SERVICE_DISABLED lifecycle evidence for radio sessions;
- adds configurable PoC SQU/PTT activity events;
- counts RTP received while PAUSED separately from RTP committed to MXF;
- exposes record/pause/keepalive/media-interval counters in Recorder summary;
- adds deterministic four-burst persistent-radio simulator;
- adds Phase 4 smoke/acceptance harness, deferred to integrated system testing.

Phase 2 File Manager remains COMPLETE_TARGET_VALIDATED. Phase 3/4 runtime gates remain materialized awaiting the later integrated target build/test campaign.
