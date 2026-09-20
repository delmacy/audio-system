# Phase 21 — Progressive Stress / Scenario Runner

## Purpose

Phase 21 introduces a progressive stress orchestration layer for the recorder PoC. It is not a single monolithic benchmark. It is a staged runner that increases the number of services, sessions, conversations, file rotations, media faults, gateway ingress paths, and playback/export checks in controlled rounds.

The goal is to prove that the system degrades explicitly and observably instead of silently losing audio, mixing services, or generating false evidence.

## Architectural rule

The stress runner must not become part of the recorder critical path.

```text
Scenario Runner
  ├─ launches CWP direct RTSP/RTP clients
  ├─ launches gateway-translated SIP/legacy scenarios
  ├─ launches fault injection rounds
  ├─ observes RecorderHost summaries
  ├─ observes Event Bus / metrics / indexer lag
  ├─ invokes playback/export checks
  └─ writes a run report

RecorderHost
  └─ keeps RTP → Media Engine → MXF independent
```

## Progressive levels

The default profile is intentionally incremental:

| Level | Services | Purpose |
| --- | ---: | --- |
| L1 | 1 | single mono service sanity |
| L2 | 5 | small operational cluster |
| L3 | 10 | multiple CWPs and service identities |
| L4 | 30 | medium load with staggered activity |
| L5 | 50 | target realistic PoC fanout |
| L6 | 100 | capacity challenge, optional |

Each service remains the Phase 9 model:

```text
1 service = 1 RTP/UDP mono flow = 1 LogicalTrackUUID = 1 MXF track
```

No RX/TX split is introduced by the stress runner.

## Scenario classes

The runner supports four scenario classes:

1. **CWP direct** — native RTSP/RTP directly into RecorderHost.
2. **Radio service** — persistent RTSP sessions with RECORD/PAUSE bursts and keepalive.
3. **Telephone/SIP via gateway** — translated ingress through Recording Gateway.
4. **Fault overlays** — packet loss, reordering, session interruption, delayed indexer, degraded observability, export retry.

## Acceptance policy

A stress round passes only when all of the following hold:

- no cross-service media contamination;
- no unexpected RX/TX split;
- every active service has a LogicalTrackUUID;
- every physical segment has a TrackInstanceUUID;
- gaps are explicit;
- P0 observability events are not silently dropped;
- File Manager does not create new files at T0;
- indexer lag stays within the configured warning/critical thresholds or reports degraded status;
- playback plans resolve the expected services and intervals;
- evidence bundle generation succeeds for at least one representative service per round.

## Failure classification

Failures are classified as:

- `PASS`
- `PASS_WITH_WARNINGS`
- `DEGRADED_EXPECTED`
- `FAIL_INTEGRITY`
- `FAIL_CROSS_CONTAMINATION`
- `FAIL_SILENT_LOSS`
- `FAIL_RUNNER_ERROR`

`DEGRADED_EXPECTED` is acceptable only when the scenario explicitly injected a fault and the recorder produced the expected gap/degraded/recovered evidence.

## Outputs

A run produces:

```text
runs/stress/<run-id>/
├── stress-run-report.json
├── stress-rounds.csv
├── service-summary.csv
├── failure-classification.json
├── recorder-summary-snapshots/
├── observability-snapshots/
├── playback-checks/
└── evidence-bundle-checks/
```

## Non-goals

This phase does not run the final full acceptance test. It prepares the orchestrator and deterministic scenario structure for that future campaign.
