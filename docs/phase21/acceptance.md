# Phase 21 Acceptance — Progressive Stress / Scenario Runner

Phase 21 is accepted when the repository contains a deterministic stress profile, a scenario runner, and a smoke harness that can generate a staged report without requiring the full recorder to be running.

## Required artifacts

- `docs/phase21/progressive-stress-scenario-runner.md`
- `docs/phase21/acceptance.md`
- `config/stress/progressive-stress.ini`
- `scenarios/stress/progressive-stress-01.json`
- `scripts/stress/19-progressive-stress-smoke.cmd`
- `scripts/stress/Invoke-ProgressiveStressSmoke.ps1`

## Required checks

The smoke harness must validate:

1. levels L1, L2, L3, L4, L5 are defined;
2. service counts are monotonic;
3. all services use `media_flow=mono`;
4. CWP direct and gateway-translated ingress are distinct;
5. no base scenario introduces RX/TX as track identity;
6. fault overlays are explicit and expected;
7. acceptance classes are generated;
8. a run report, round CSV and service CSV are produced.

## Future integrated acceptance

The final integrated campaign will additionally require real RecorderHost execution, real RTSP/RTP traffic, MXF output, temporal index ingestion, playback plan resolution and evidence bundle verification.
