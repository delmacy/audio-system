# Phase 5 / 5.0.0 — Multi-session / CWP Routing

Materialized one-process multi-session routing on top of the Phase 4 persistent radio session.

## Added

- `RecorderHost` with bounded session/client tables (`MAX_SESSIONS=64`, `MAX_CLIENTS=64`).
- One shared RTSP listener with multiple concurrent TCP clients.
- One RTP UDP socket, GStreamer pipeline, StorageWriter and identity context per configured session.
- `session-map.tsv` routing materialization loaded before HOST_READY.
- Route ownership events: `ROUTE_BOUND`, `RTP_ROUTE_ACTIVE`, `ROUTE_COLLISION`, `ROUTE_REJECTED`.
- Route-local asynchronous TEARDOWN/finalization: closing one session does not block the Recorder Host or other sessions while MXF EOS/footer/flush completes.
- Host READY document containing all configured routes, ports and LT/TI values.
- Per-session summary plus host aggregate summary.
- Six-CWP concurrent routing scenario and deferred smoke gate.
- Direction-aware radio simulator preserving Phase 4 RX defaults.

## Compatibility

The Phase 3/4 single-session command line remains supported when `--session-map` is absent. The legacy `RECORDER SUMMARY ...` line remains emitted for single-session mode.

## Deferred to integrated acceptance

- Windows target build and Phase 3/4 regression execution;
- Phase 5 six-session / five-CWP smoke execution;
- crash/durability/recovery/endurance;
- 50/100 live-session stress;
- RTCP and later SIP/Gateway integration.
