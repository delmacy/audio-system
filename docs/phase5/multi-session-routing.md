# Phase 5 — Multi-session / CWP Routing

## Objective

Turn the Phase 3/4 single-session Recorder into one persistent Windows service capable of owning several independent RTSP/RTP recording sessions concurrently, without changing the semantic identity or StorageWriter contracts already proven.

The Phase 5 target topology is:

```text
                    one recorder-host.exe
                           |
                    one RTSP listener
                           |
       +-------------------+-------------------+
       |                   |                   |
   Session A           Session B           Session N
   RTSP state          RTSP state          RTSP state
   RTP socket          RTP socket          RTP socket
   LT/TI               LT/TI               LT/TI
   pipeline            pipeline            pipeline
   StorageWriter       StorageWriter       StorageWriter
   MXF A               MXF B               MXF N
```

The first materialized scenario uses six logical recording routes across five CWPs in one host process. The compile-time bounds are 64 sessions and 64 RTSP clients, with `FD_SETSIZE=256` so listener + RTSP sockets + RTP sockets fit in the Windows `select()` set for this PoC scale.

## Deterministic routing

Phase 5 introduces `session-map.tsv`. Each row declares one recording route before RTSP traffic starts:

- route key;
- endpoint/service/direction;
- activity signal policy;
- DisplayName;
- LogicalTrackUUID;
- TrackInstanceUUID;
- FileId and paths;
- RTP port;
- logical window metadata;
- session kind.

All StorageWriters, GStreamer pipelines and RTP sockets are opened before `HOST_READY`.

`ANNOUNCE` resolves the URI to exactly one route. Unknown routes are rejected; a second RTSP connection cannot claim a route already owned by another connection.

After route binding, RTP dispatch does not re-resolve semantic identity packet by packet. Windows `select()` identifies the UDP socket that became readable and that socket already belongs to one `RecorderSession`. This keeps the media hot path deterministic.

## Session isolation

Each `RecorderSession` owns its own:

- RTSP Session ID;
- ANNOUNCE/SETUP/RECORD/PAUSE/TEARDOWN state;
- RTP sequence/timestamp state;
- media counters;
- GStreamer pipeline;
- MXF identity pad;
- StorageWriter file handle;
- lock sidecar;
- finalization state.

A PAUSE on route A does not affect B. A TEARDOWN on A detaches only A from the RTP hot path and queues A for a dedicated finalizer thread. EOS/footer generation, `FlushFileBuffers` and rename for A therefore do not block RTSP/RTP service for B..N. The host remains alive while any configured route is still open or finalizing.

## Evidence

The first received RTP packet on each socket generates `RTP_ROUTE_ACTIVE`, carrying the route key and bound RTP port. Together with `ROUTE_BOUND`, unique LT/TI/ports, route-specific packet cardinalities and zero route-collision events, this is the Phase 5 routing evidence.

The six-session scenario intentionally gives each route a different active-packet count. This is not a cryptographic contamination proof, but it makes accidental cross-routing visible at the integration gate and complements the structural one-socket/one-session dispatch rule.

## Backward compatibility

When `--session-map` is omitted, the Phase 3/4 command-line arguments synthesize a single session. The legacy `RECORDER SUMMARY ...` line is still emitted for that mode, preserving the existing smoke parsers.

## Deferred

The following remain for later system integration rather than blocking Phase 5 materialization:

- target Windows build and six-session / five-CWP smoke execution;
- 50/100 live session stress;
- RTCP semantics;
- crash/durability/recovery;
- dynamic topology changes while the host is live;
- SIP / Recording Gateway;
- two-sided CWP-A/CWP-B lab;
- media-bank replay and full Scenario Runner.
