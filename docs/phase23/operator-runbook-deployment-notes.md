# Phase 23 — Operator Runbook / Deployment Notes

Version: 23.0.0  
Scope: Windows-native PoC operation guide for the recorder system.

## Purpose

This phase does not introduce a new recording protocol. It turns the materialized PoC into an operator-oriented package:

- prerequisites checklist;
- boot order;
- smoke gate order;
- progressive acceptance campaign order;
- troubleshooting notes;
- evidence vs simulation warnings;
- expected report locations;
- stop/cleanup guidance.

The runbook is intentionally conservative: a gate that was not executed is `NOT_RUN` or `BLOCKED`, never `PASS`.

## Canonical operating model

```text
CWP direct protocol
  CWP simulator -> RTSP/RTP -> Recorder

Translated protocol
  SIP / legacy radio adapter -> Recording Gateway -> RTSP/RTP -> Recorder

Playback / evidence
  Closed MXF + manifest + SQLite Temporal Index -> Playback plan -> Export bundle
```

The live branch is operational preview only. It must not be treated as evidence.

## Non-negotiable invariants

```text
1 service = 1 mono RTP/UDP media flow = 1 LogicalTrackUUID = 1 MXF track
```

`RX`, `TX`, controller, pilot, telephone role, SQU, PTT and call state are metadata, role semantics or timeline events. They are not default MXF audio tracks.

## Directory assumptions

The operator should extract the package to a short Windows path, for example:

```powershell
C:\recorder-poc
```

Avoid paths with non-ASCII characters, deep nesting, or cloud-synced folders during stress tests.

Recommended working layout:

```text
C:\recorder-poc\
├── config\
├── scripts\
├── src\
├── web\
├── media-bank\
├── runs\
└── recordings\
```

## Prerequisites

Known PoC dependencies:

- Windows native host, administrator shell for network setup;
- GStreamer MSVC runtime + development package;
- FFmpeg available on PATH or configured location;
- Visual Studio Build Tools / MSBuild when compiling native components;
- Wireshark/dumpcap for external witness capture;
- SQLite tooling when inspecting temporal index manually.

The PoC is not Docker/Hyper-V based. It is designed for native Windows operation.

## Environment checks

Run from an elevated PowerShell when network or packet capture setup is involved:

```powershell
.\scripts\network\01-inventory.cmd
.\scripts\network\04-smoke-test.cmd
.\scripts\mxf\Test-NativePrereqs.ps1
```

Expected result: network profile known, loopback/lab addresses available, GStreamer/FFmpeg/MSBuild discoverable where required.

## Suggested first boot order

1. Prepare Windows/network lab.
2. Build recorder host and MXF identity components.
3. Run one-CWP smoke.
4. Run persistent radio smoke.
5. Run multi-session smoke.
6. Run media engine protection smoke.
7. Run window rotation smoke.
8. Run gateway smoke.
9. Run service perspective matrix smoke.
10. Initialize temporal index.
11. Run observability/event bus smoke.
12. Run playback/export/player smokes.
13. Run integrity/fault/stress gates.
14. Run integrated acceptance aggregation.

## Canonical command sequence

```powershell
# Network foundation
.\scripts\network\01-inventory.cmd
.\scripts\network\03-setup-lab.cmd
.\scripts\network\04-smoke-test.cmd

# Native prereqs / build
.\scripts\mxf\Test-NativePrereqs.ps1
.\scripts\recorder\01-build-recorder-host.cmd

# Recorder path
.\scripts\recorder\02-one-cwp-smoke.cmd
.\scripts\recorder\03-radio-persistent-session-smoke.cmd
.\scripts\recorder\04-multi-cwp-routing-smoke.cmd
.\scripts\recorder\05-media-engine-smoke.cmd
.\scripts\recorder\06-window-rotation-smoke.cmd
.\scripts\recorder\07-recording-gateway-smoke.cmd
.\scripts\recorder\08-service-perspective-matrix-smoke.cmd

# Index / observability / playback
.\scripts\indexer\09-temporal-index-smoke.cmd
.\scripts\observability\10-observability-event-bus-smoke.cmd
.\scripts\playback\11-historical-playback-smoke.cmd
.\scripts\playback\12-playback-segment-export-smoke.cmd
.\scripts\player\13-web-player-shell-smoke.cmd
.\scripts\player\14-player-interaction-modes-smoke.cmd
.\scripts\player\15-live-player-branch-smoke.cmd

# Evidence / resilience / stress / acceptance
.\scripts\export\16-export-evidence-bundle-smoke.cmd
.\scripts\integrity\17-integrity-manifest-chain-smoke.cmd
.\scripts\fault\18-fault-injection-recovery-smoke.cmd
.\scripts\stress\19-progressive-stress-smoke.cmd
.\scripts\acceptance\20-integrated-acceptance-plan-smoke.cmd
```

## Fast documentation-only validation

This phase includes a runbook smoke that validates the presence and consistency of operational files without claiming the recorder passed the integrated campaign:

```powershell
.\scripts\runbook\21-operator-runbook-smoke.cmd
```

This smoke is a documentation/package gate. It is not an evidential recording gate.

## Report interpretation

Use these terms consistently:

- `PASS`: gate executed and met its acceptance criteria.
- `PASS_WITH_WARNINGS`: gate executed and all critical invariants passed, but warnings exist.
- `DEGRADED_EXPECTED`: injected fault caused expected degraded behavior and explicit recovery/gap reporting.
- `BLOCKED`: required gate was not run or prerequisite missing.
- `NOT_RUN`: gate has no execution record in the current campaign.
- `FAIL_INTEGRITY`: evidence or hash chain failed.
- `FAIL_CROSS_CONTAMINATION`: service identity or media crossed between services.
- `FAIL_SILENT_LOSS`: loss occurred without explicit gap/event/status.
- `FAIL_RUNNER_ERROR`: harness itself failed.

## Evidence warnings

The following are not evidence of recorded audio:

- live preview buffer;
- synthetic silence inserted for continuous playback presentation;
- simulated WAV produced by a harness;
- fixture JSON;
- UI-only state.

Evidence chain begins only when closed media, manifests, source maps, index entries and hashes are available and verified.

## Troubleshooting quick map

| Symptom | First check | Likely area |
|---|---|---|
| Recorder does not bind | port conflict / lab IP missing | network setup |
| No RTP captured | wrong address/port/PT | scenario route/media engine |
| MXF has wrong identity | TrackName/LT/TI plugin path | MXF identity plugin |
| UI shows no media | playback plan missing segment | temporal index/playback API |
| Export has gap but no event | source-map/gaps generation | export evidence bundle |
| Integrated report says BLOCKED | missing gate result | acceptance aggregator |
| Stress fails silently | expected event not emitted | fault/observability path |

## Operator stop order

1. Stop scenario runner.
2. Stop simulators/gateways.
3. Stop recorder after graceful TEARDOWN/finalization.
4. Verify `.partial` files and `.lock` sidecars.
5. Run recovery inspection if stale partial files remain.
6. Run integrity verification before deleting any run output.

## Cleanup guidance

Do not delete `runs/`, `recordings/`, manifests or SQLite files from a campaign until the integrated report and evidence bundles have been reviewed. For repeat testing, create a new run directory rather than overwriting previous evidence.
