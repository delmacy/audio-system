# Phase 12 — Async Event Bus and Observability

## Goal

Keep the recording path independent from logging, metrics, indexing, dashboards and alarms.

```text
RTP -> Media Engine -> MXF writer
                |
                +-> bounded Event Bus -> sinks
                                      |- audit JSONL
                                      |- Prometheus textfile/export endpoint
                                      |- temporal indexer feed
                                      `- alarms/diagnostics
```

The producer performs a bounded in-memory enqueue only. No database transaction, filesystem flush, dashboard request or network export is allowed to block media ingestion.

## Priority lanes

- P0 critical evidence: session loss, gap boundaries, topology change, integrity failure. Must never be silently discarded. If its bounded lane cannot accept an event, the Recorder raises `OBSERVABILITY_INTEGRITY_FAILURE`, persists an emergency sidecar record and exposes an alarm.
- P1 operational evidence: call/radio signaling and reconnection. Prefer preservation; may spill to disk under prolonged sink outage.
- P2 aggregate telemetry: counters, queue depth, rates and routine statistics. Coalesce by key; old samples may be replaced by newer samples.
- P3 diagnostics: parser/debug traces. Drop first under pressure.

## Backpressure contract

1. Recording continues while sinks are slow or unavailable.
2. P3 drops first, then P2 coalesces.
3. P1 may use bounded disk spill.
4. P0 is never silently dropped. Failure to preserve P0 is itself a P0 integrity alarm.
5. Every lane exposes accepted, exported, coalesced, spilled and dropped counters.
6. No packet-level human logging.

## Metrics model

Host:
- `recorder_sessions_configured`
- `recorder_sessions_active`
- `recorder_rtp_packets_total`
- `recorder_rtp_bytes_total`
- `recorder_media_gaps_total`
- `recorder_writer_queue_depth`
- `recorder_event_bus_queue_depth{priority}`
- `recorder_event_bus_dropped_total{priority}`
- `recorder_event_bus_spilled_total{priority}`
- `recorder_event_bus_exported_total{sink}`
- `recorder_indexer_lag_seconds`

Per service/session labels are deliberately bounded: service id, endpoint id and session slot. Do not use FileId, TrackInstanceUUID, call-id or packet sequence as metric labels because they create unbounded cardinality.

## Audit versus metrics

Audit events are append-only evidence with identifiers and UTC timestamps. Metrics are lossy aggregate observations. Metrics never replace audit evidence; audit events never become per-packet traces.

## Failure isolation

- JSONL sink failure: retain queue/spill, raise sink health alarm.
- Prometheus sink failure: metrics remain in memory; recording continues.
- SQLite/indexer failure: event feed/checkpoint remains replayable; recording continues.
- Event consumer crash: producer remains operational.

## Deferred integrated proof

The Phase 12 smoke later generates mixed P0–P3 load, intentionally stalls sinks, and proves:

- media producer continues;
- P0 accepted/exported count remains exact;
- P3 drops occur before P1/P0 loss;
- P2 coalescing reduces queue pressure;
- metrics output is parseable;
- audit JSONL remains ordered per producer sequence;
- queue depth returns to zero after sink recovery.
