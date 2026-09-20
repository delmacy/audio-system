# Phase 20 Acceptance

The Phase 20 smoke is acceptable when it can generate a deterministic fault report with these properties:

- every injected fault has a corresponding observed event;
- RTP loss yields `GAP_START`/`GAP_END` or sequence-gap metrics;
- duplicate/out-of-order packets are dropped and counted;
- stale partial files are not promoted as complete evidence;
- stopped indexer can catch up from checkpoint or rebuild sources;
- observability degradation emits explicit degraded/recovered events;
- export retry produces a final report with no duplicate evidence rows;
- final recovery summary is `PASS` only when every required fault was observed.
