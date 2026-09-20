# Canonical State Machines

## Radio/CWP recording session
DISABLED
  -> SETUP
  -> READY
  -> RECORDING (on media activity)
  -> READY (on PAUSE)
  -> RECORDING (repeat as needed)
  -> CLOSED (on TEARDOWN)

Open RTSP session is not equivalent to active media.

## Endpoint connectivity
OFFLINE
  -> STARTING
  -> CONNECTED
  -> ONLINE
  -> CONNECTION_SUSPECT
  -> CONNECTION_LOST
  -> RECONNECTED
  -> ONLINE

Graceful stop:
ONLINE -> TEARDOWN -> DISCONNECTED

Abrupt stop:
ONLINE -> missed liveness -> CONNECTION_SUSPECT -> CONNECTION_LOST

## Recording track watermarks
LAST_RECEIVED >= LAST_WRITTEN >= LAST_DURABLE

Expose:
- write_lag_ms = last_received - last_written
- durability_lag_ms = last_received - last_durable

Anything after the last durable watermark at crash time must be recovered/verified; never silently declared durable.

## Recording file lifecycle

`ALLOCATED -> RECORDING_LOCKED -> FINALIZING -> CLOSED_COMPLETE`

Crash branch:

`RECORDING_LOCKED -> STALE_LOCK -> RECOVERY_REQUIRED | RECOVERABLE_INCOMPLETE`

Rules:
- `.mxf.partial` means not finalized.
- `.mxf.lock` means an operational owner/state record exists.
- OS handle protection, not the sidecar alone, blocks delete/rename while recording.
- A stale lock after crash is recovery evidence; it is never interpreted as normal silence.

## Topology application policy

Configured policy is `immediate` or `next_boundary`.

- `immediate`: finalize current physical MXF part and open the new topology immediately.
- `next_boundary`: stage administrative removal/rename/reordering until the next file boundary.
- safety override: a required new recording source that cannot fit the open MXF forces immediate rollover rather than dropping media.

The Web Player continuity key is `LogicalTrackUUID`, not physical TrackIndex.

## File Manager next-window lifecycle

`PLANNED -> PRECREATING -> PRECREATED -> LOCKED -> ARMED -> RECORDING -> FINALIZING -> CLOSED_COMPLETE`

Boundary rule:
- all required next-window files must reach `ARMED` before the configured READY deadline;
- no physical file creation is allowed on the T0 boundary path;
- at T0, already-open writer handles are activated for the new logical window;
- incomplete READY barrier => `BOUNDARY_SPILL_REQUIRED`; current writer(s) remain authoritative until replacement writer(s) are ready.

Temporal fields are not interchangeable:
- physical/audit: `FileCreatedUTC`, `FileArmedUTC`;
- logical ordering: `RecordingWindowStartUTC`, `SegmentSequence`;
- media: `FirstMediaUTC`, `LastMediaUTC`.

### Phase 4 persistent radio invariant

`READY` may persist for arbitrary silent intervals while the radio service remains enabled. Keepalive/liveness traffic does not transition the session into `RECORDING`. Repeated activity uses the same session/file:

`READY -> RECORDING -> READY -> RECORDING -> ... -> READY -> TEARDOWN -> CLOSED`

No new file or RTSP session is created merely because an activity interval ended.
