# Phase 12 — 12.0.0

Materializes the asynchronous Event Bus and observability boundary.

- four priority lanes P0–P3;
- zero-silent-loss contract for P0;
- P2 coalescing and P3 drop-first pressure policy;
- bounded P1 disk-spill contract;
- JSONL audit sink;
- Prometheus-compatible metrics snapshot;
- replayable temporal-index feed contract;
- bounded metric label cardinality;
- deferred sink-stall smoke harness.

Recording remains independent from observability sinks.
