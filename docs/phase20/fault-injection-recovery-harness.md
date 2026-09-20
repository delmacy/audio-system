# Phase 20 — Fault Injection / Recovery Harness

## Goal

Phase 20 creates a controlled harness to inject operational failures without turning them into silent corruption.

It targets:

- RTP loss and sequence gaps
- RTP duplicate/out-of-order packets
- RTSP session drop and reconnect
- recorder process crash during `.mxf.partial`
- stale `.mxf.lock` recovery classification
- temporal indexer stopped/restarted
- observability sink degradation
- export failure and retry

## Principle

A failure may produce an explicit gap, incomplete file, degraded observability status or recovery report. It must not produce unreported media loss, unreported cross-track contamination or silent evidence mutation.

## Recovery states

```text
CLOSED_COMPLETE
RECOVERED_INCOMPLETE
CORRUPTED
GAP_REPORTED
INDEX_REBUILT
EXPORT_RETRIED
OBSERVABILITY_DEGRADED
OBSERVABILITY_RECOVERED
```

## Acceptance intent

The future integrated test must prove that injected faults appear as explicit events and reports while the recorder preserves closed evidence and does not fabricate audio.
