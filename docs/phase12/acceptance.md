# Phase 12 acceptance — deferred integrated campaign

PASS requires:

- async producer enqueue independent of sinks;
- four priority lanes P0–P3;
- zero silent P0 loss;
- explicit dropped/coalesced/spilled counters;
- JSONL audit sink;
- Prometheus-compatible metrics snapshot;
- replayable temporal-index feed;
- bounded metric label cardinality;
- no per-RTP-packet human logs;
- sink stall does not stop RTP/MXF processing;
- queue recovery drains within configured deadline.

Future command:

```powershell
scripts\observability\10-observability-event-bus-smoke.cmd
```
