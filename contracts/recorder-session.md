# Minimal Recorder Session Contract — Phase 3

## Vertical slice

Phase 3 establishes one live recording session end-to-end:

`CWP simulator -> RTSP control + RTP/PCMA -> Recorder Host -> mxfidmux -> StorageWriter -> MXF`

The first slice is intentionally one session / one logical track. Scale-out must preserve this contract rather than replace it.

## Control state

`DISCONNECTED -> ANNOUNCED -> SETUP -> READY -> RECORDING <-> READY -> TEARDOWN -> CLOSED`

- `ANNOUNCE` carries SDP and must declare PCMA / payload type 8 for this slice.
- `SETUP` allocates/advertises the Recorder RTP port.
- `RECORD` opens the media gate.
- `PAUSE` closes the media gate without closing the RTSP session or file writer.
- `GET_PARAMETER` is a liveness/control operation and must not create a human audit line on every successful keepalive in later scale tests.
- `TEARDOWN` requests graceful end-of-session and file finalization.

## Media contract

- RTP version 2.
- Payload type 8 (G.711 A-law / PCMA).
- 8000 samples/s, mono.
- Normal packetization: 20 ms / 160 payload bytes.
- RTP sequence discontinuity is evidence; it is not interpreted as silence.
- Packet logging is aggregated. Individual packets are not persisted as audit events.

## Storage boundary

Phase 3 deliberately does **not** use GStreamer `filesink`.

`appsrc -> mxfidmux -> appsink -> Win32 StorageWriter`

Rationale:

1. Recorder code owns the Windows file handle.
2. Active `.mxf.partial` is opened with `FILE_SHARE_READ` only, therefore delete/rename sharing is denied.
3. The same boundary can later call `FlushFileBuffers` and publish durable-watermark evidence.
4. GStreamer remains responsible for MXF serialization/finalization, while file lifecycle remains a Recorder/File-Manager concern.

## File lifecycle

`ALLOCATED -> RECORDING_LOCKED -> FINALIZING -> CLOSED_COMPLETE`

On graceful close:

1. stop accepting media;
2. send EOS into the GStreamer graph;
3. wait for MXF EOS/footer/index completion;
4. `FlushFileBuffers` on the Recorder-owned handle;
5. close handle;
6. rename `.mxf.partial -> .mxf` with write-through semantics;
7. remove `.mxf.lock`.

Failure before proof of the above leaves the partial/lock evidence for recovery assessment.

## Identity

One MXF track embeds:

`<DisplayName> | LT=<LogicalTrackUUID> | TI=<TrackInstanceUUID>`

- `LogicalTrackUUID`: stable semantic identity.
- `TrackInstanceUUID`: one physical occurrence in this MXF.
- MXF TrackID/TrackNumber retain native structural meaning.

## Temporal model

The first recorder-host accepts `RecordingWindowStartUTC` and `SegmentSequence` as lifecycle metadata even though the dedicated MXF Descriptive Metadata scheme is deferred.

Physical creation time and logical recording-window time remain distinct.

## Phase 4 radio persistence extension

For `session_kind=radio`, `SETUP` enables the logical radio service. The RTSP session and writer remain open across any number of `RECORD <-> PAUSE` transitions. `PAUSE` is not a topology change and does not create a new TrackInstanceUUID. `TEARDOWN` is the service-disable boundary and is the only normal operation in this slice that closes the persistent session/file.

Post-SETUP RTSP operations must carry the active Session ID. A missing/mismatched Session header is rejected as `454 Session Not Found` and recorded as an integrity warning.

RTP received while READY/PAUSED is network evidence but not recorded media. It is counted in `rtp_packets_ignored_not_recording`.

## Phase 5 multi-session extension

Phase 5 replaces the single runtime `RecorderContext` assumption with a bounded `RecorderHost` session table. One process owns one RTSP listener and up to 64 configured recording sessions. Each configured session owns independently:

- RTSP Session ID and state machine;
- route key;
- RTP UDP socket/port;
- GStreamer pipeline and `appsrc`;
- `mxfidmux` request pad identity;
- Recorder-owned `StorageWriter` and `.mxf.partial` handle;
- LogicalTrackUUID / TrackInstanceUUID;
- counters and activity state.

The `session-map.tsv` is the authoritative Phase 5 routing materialization. An `ANNOUNCE` URI claims exactly one preconfigured route. A second client cannot claim an active route. Unknown routes are rejected. Once bound, RTP dispatch is determined by the UDP socket that became readable; the socket already belongs to exactly one session, so RTP does not perform best-effort semantic lookup on the media hot path.

`TEARDOWN` is route-local: the route is detached from the RTP hot path and its pipeline/writer is finalized on a dedicated worker thread. EOS/footer/flush work for one route does not block the RTSP/RTP loop for other sessions. The Recorder Host exits normally only after all configured sessions have finalized (or the host-wide safety timeout is reached).

The legacy one-session command line remains supported so Phase 3/4 gates continue to exercise the same executable.
