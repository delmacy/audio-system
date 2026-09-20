# Phase 5 Acceptance — Multi-session / CWP Routing

Deferred integrated command:

```powershell
scripts\recorder\04-multi-cwp-routing-smoke.cmd
```

PASS requires all of the following in one `recorder-host.exe` process:

- 6/6 configured routes are present in READY;
- 6 unique RTSP Session IDs;
- 6 unique LogicalTrackUUIDs;
- 6 unique TrackInstanceUUIDs;
- 6 unique RTP ports;
- exactly one `ROUTE_BOUND` event per route;
- exactly one `RTP_ROUTE_ACTIVE` event per route;
- zero `ROUTE_COLLISION` and zero `ROUTE_REJECTED` events;
- zero `INTEGRITY_FAILURE` events;
- per-route RECORD/PAUSE/media-interval counts match the scenario;
- route-specific active RTP packet counts match their unique expected values;
- RTP intentionally sent during PAUSE is counted as ignored and is not recorded;
- sequence-gap count remains zero for the deterministic simulator;
- all six sessions receive graceful TEARDOWN;
- all six `.mxf.partial` files become final `.mxf` files;
- all six lock sidecars are removed on graceful close;
- Recorder Host exits only after all configured sessions are finalized.

This gate validates routing/isolation mechanics. Full packet-content contamination analysis, durability and large-scale session stress remain part of later integrated acceptance.
