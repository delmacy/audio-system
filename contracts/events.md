# Canonical Event Vocabulary

## Session lifecycle
- SESSION_OPEN
- SETUP
- READY
- KEEPALIVE_OK (counter/diagnostic; not one human log line per event)
- KEEPALIVE_MISSED
- RECORD
- PAUSE
- TEARDOWN
- SESSION_CLOSE

## Telephony
- RING_START
- ANSWER
- CANCEL
- RELEASE

## Radio
- PTT_ON
- PTT_OFF
- SQU_ON
- SQU_OFF

## Media
- MEDIA_START
- MEDIA_END
- MEDIA_COMMIT

## Connectivity
- CONNECTED
- CONNECTION_SUSPECT
- CONNECTION_LOST
- RECONNECTED
- DISCONNECTED

## Integrity / gaps
- GAP_START
- GAP_END
- RECOVERY_START
- RECOVERY_COMPLETE
- INTEGRITY_WARNING
- INTEGRITY_FAILURE

## Topology
- TOPOLOGY_CHANGE
- ENDPOINT_ENABLED
- ENDPOINT_DISABLED
- SERVICE_ENABLED
- SERVICE_DISABLED

## Severity policy
P0 — never discard:
- CONNECTION_LOST
- GAP_START/GAP_END
- SESSION_OPEN/SESSION_CLOSE
- TOPOLOGY_CHANGE
- INTEGRITY_FAILURE

P1 — preserve preferentially:
- ANSWER
- RING_START
- CANCEL
- RELEASE
- PTT_ON/PTT_OFF
- SQU_ON/SQU_OFF
- RECONNECTED

P2 — aggregate/counter:
- KEEPALIVE_OK
- RTP packet/byte statistics
- queue statistics
- routine media statistics

P3 — debug only:
- parser traces
- packet-level diagnostics
- verbose internal transitions

### Track topology detail
- TRACK_ADDED
- TRACK_REMOVED
- TRACK_RELOCATED
- TRACK_RENAMED
- FILE_ROLLOVER

`TRACK_RELOCATED` means the same `LogicalTrackUUID` moved to a different physical TrackIndex in a subsequent file/topology. It is informational, not an identity change.

## File/window manager
- NEXT_WINDOW_PLANNED
- NEXT_WINDOW_PRECREATE_START
- NEXT_WINDOW_READY_BARRIER
- NEXT_WINDOW_ARMED
- WINDOW_ACTIVATION_BARRIER_RELEASED
- WINDOW_ACTIVATED
- BOUNDARY_SPILL_REQUIRED

### Phase 4 aggregation rule

Successful `GET_PARAMETER` requests increment an in-memory keepalive counter. At persistent-session close, one aggregate `KEEPALIVE_OK` evidence event may be written with the count. Do not emit one human audit record per successful keepalive.

## Phase 12 observability health
- OBSERVABILITY_SINK_DEGRADED
- OBSERVABILITY_SINK_RECOVERED
- OBSERVABILITY_QUEUE_PRESSURE
- OBSERVABILITY_P1_SPILL_STARTED
- OBSERVABILITY_P1_SPILL_DRAINED
- OBSERVABILITY_INTEGRITY_FAILURE

`OBSERVABILITY_INTEGRITY_FAILURE` is P0 and means the system could not preserve a required P0 evidence event. It must never be hidden by the observability subsystem itself.
