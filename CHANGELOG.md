
## Phase 25 / 25.0.0

- Added closure/open risks/backlog package.
- Added root `AGENTS.md` and `CODEX.md`.
- Added closure static smoke gate.

# Changelog

- Phase 19 — Integrity / Manifest Chain — included.
- Phase 20 — Fault Injection / Recovery Harness — materialized.

## Phase 21 — 21.0.0

Progressive Stress / Scenario Runner materialized. Adds staged service fanout, CWP direct vs gateway-translated ingress, explicit fault overlays and deterministic stress run reports while preserving the one-service/one-mono-track model.


# CHANGELOG — Phase 22 / 22.0.0

## Added

- Integrated Acceptance Plan documentation.
- Integrated campaign configuration.
- Integrated acceptance scenario spanning Phase 1 through Phase 21.
- Deterministic PowerShell harness for aggregation smoke.
- Final report contract for JSON, Markdown and CSV outputs.

## Preserved

- CWP direct RTSP/RTP path to Recorder.
- Gateway limited to translated ingress.
- Mono service media model.
- LogicalTrackUUID and TrackInstanceUUID identity split.
- Live branch not treated as evidential audio.
- Synthetic silence not treated as recorded evidence.

## Notes

This phase materializes acceptance orchestration. The deterministic smoke validates report aggregation and gating semantics; it does not replace real native Windows execution of each gate.


## Phase 23 — 23.0.0

- Added operator runbook and deployment notes.
- Added runbook smoke gate.
- Preserved evidence/simulation distinction and mono service invariant.

## Phase 24 / 24.0.0

Added Final PoC Packaging / Release Candidate documentation and packaging smoke gate.
