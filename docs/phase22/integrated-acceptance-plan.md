# Phase 22 — Integrated Acceptance Plan / 22.0.0

## Purpose

Phase 22 consolidates the individual materialized gates into a single integrated acceptance campaign. The campaign does not redefine the architecture; it verifies that the previously defined components can be executed in a controlled order and that their evidence can be reconciled into one acceptance report.

The campaign links:

1. Windows-native host/network foundation.
2. MXF identity, file lifecycle, lock and pre-arm behavior.
3. Recorder host and CWP direct RTSP/RTP path.
4. Persistent radio sessions.
5. Multi-session routing.
6. RTP/media engine protection.
7. Window rotation.
8. Recording Gateway for SIP/legacy translated ingress.
9. Service-perspective mono matrix.
10. Media Bank and scenario generation.
11. SQLite temporal index.
12. Observability and asynchronous event bus.
13. Historical playback plan.
14. Playback segment export.
15. Web player shell and interaction modes.
16. Live player branch.
17. Evidence export bundle.
18. Manifest/integrity chain.
19. Fault injection and recovery.
20. Progressive stress scenario runner.

## Non-goals

This phase is not a new recorder implementation and not a production certification package. It is an integrated acceptance harness for the PoC tree. It must not silently convert unexecuted gates into PASS. A gate can be `NOT_RUN`, `BLOCKED`, `PASS`, `WARN`, or `FAIL`, but not assumed.

## Canonical campaign sequence

The default acceptance order is:

```text
00-prerequisites
01-network
02-mxf-identity-file-manager
03-recorder-one-cwp
04-radio-persistent-session
05-multi-session-routing
06-media-engine-rtp-protection
07-window-rotation
08-recording-gateway
09-service-perspective-matrix
10-media-bank
11-temporal-index
12-observability-eventbus
13-historical-playback
14-segment-export
15-web-player-shell
16-player-interaction-modes
17-live-player-branch
18-evidence-bundle
19-integrity-manifest-chain
20-fault-injection-recovery
21-progressive-stress
22-final-report
```

## Required invariants

The campaign preserves the frozen architectural invariants:

```text
CWP -> RTSP/RTP direct -> Recorder
Telefonia SIP -> Gateway -> RTSP/RTP -> Recorder
Radio fisico/legado -> Gateway/adapter -> RTSP/RTP -> Recorder
```

and:

```text
1 service/frequency/channel/logical service
= 1 mono audio flow
= 1 LogicalTrackUUID
= 1 MXF track
```

No base RX/TX split is allowed in the integrated acceptance fixtures. RX/TX can remain Media Bank role metadata, but not Recorder/MXF track identity.

## Evidence model

Each gate should emit at least one machine-readable result under:

```text
runs/acceptance/<run-id>/gates/<gate-id>/gate-result.json
```

The final report aggregates:

```text
runs/acceptance/<run-id>/integrated-acceptance-report.json
runs/acceptance/<run-id>/integrated-acceptance-report.md
runs/acceptance/<run-id>/integrated-acceptance-summary.csv
```

## Result statuses

Allowed gate statuses:

```text
PASS
WARN
FAIL
BLOCKED
NOT_RUN
```

Final campaign verdicts:

```text
PASS
PASS_WITH_WARNINGS
BLOCKED
FAIL
```

`NOT_RUN` gates are acceptable only when explicitly marked optional or capacity-challenge. Required `NOT_RUN` gates force `BLOCKED`.

## Evidence-critical failures

The following conditions are always final failures:

```text
silent media loss
cross-service contamination
P0 event silently dropped
LogicalTrackUUID mismatch
TrackInstanceUUID/source-map mismatch
unreported gap
export bundle hash mismatch
manifest chain mismatch
live buffer treated as evidence
synthetic silence treated as recorded evidence
```

## Acceptance output

The final campaign report must include:

- host and tool assumptions;
- run id and timestamps;
- ordered gate list;
- status per gate;
- evidence path per gate;
- required/optional classification;
- failure classification;
- frozen architecture invariant checks;
- final verdict.

## Important caveat

This phase materializes the integrated acceptance plan and a deterministic smoke harness. It does not claim that the full native Windows system has been executed end-to-end in this environment.
