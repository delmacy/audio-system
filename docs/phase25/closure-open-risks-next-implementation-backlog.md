# Phase 25 — Closure / Open Risks / Next Implementation Backlog

## Goal

Close the current PoC materialization sequence with a clear boundary between:

- what has been architected and materialized,
- what has been validated in earlier local gates,
- what remains to be executed on the Windows target host,
- what remains real implementation work,
- what must not be overclaimed as evidence or compliance.

This phase also adds a root `AGENTS.md` and `CODEX.md` so a future agent can resume the project with full context.

## Deliverables

- `AGENTS.md`: canonical full-scope agent handoff.
- `CODEX.md`: short pointer and invariant list for Codex-style sessions.
- `docs/phase25/closure-open-risks-next-implementation-backlog.md`
- `docs/phase25/acceptance.md`
- `config/closure/closure-backlog.ini`
- `scenarios/closure/closure-backlog-01.json`
- `scripts/closure/23-closure-backlog-smoke.cmd`
- `scripts/closure/Invoke-ClosureBacklogSmoke.ps1`

## Closure position

The PoC now has a coherent artifact chain:

```text
Network / MXF / Identity / File Manager
  -> Recorder / Gateway / CWP / Media Engine
  -> Window Rotation / Service Matrix
  -> SQLite Temporal Index
  -> Event Bus / Observability
  -> Playback / Export / Web Player
  -> Integrity / Fault Injection / Stress
  -> Integrated Acceptance / Runbook / RC Packaging
  -> Closure / Backlog / AGENTS handoff
```

The project is not automatically production-ready. Phase 25 intentionally refuses to turn materialized work into validated claims.

## Non-negotiable boundaries

```text
NOT_RUN != PASS
fixture != evidence
live buffer != evidence
synthetic silence != recorded audio
CWP direct != Gateway path
RX/TX folder role != MXF track model
TrackIndex != stable identity
```

## Open risks

1. Real MXF decode/export by TrackInstanceUUID still needs implementation/validation.
2. Continuous real-time ingest at high scale still needs target-host campaign execution.
3. Durability and `LAST_RECOVERABLE` vs `LAST_DURABLE` need empirical validation.
4. Exact ED-137/profile conformance remains unverified.
5. Windows file locking/antivirus/indexer interference must be tested on the deployment machine.
6. Observability backpressure behavior must prove P0 is never silently dropped.
7. Operator UI must label live/fixture/simulation/evidence distinctly.

## Next implementation backlog

### A. Static closure/runbook validation

- Run closure smoke.
- Run release packaging smoke.
- Run operator runbook smoke.
- Repair missing files or command references.

### B. Real recorder execution

- Build native recorder host.
- Execute one-CWP smoke.
- Execute radio persistent smoke.
- Execute multi-session routing smoke.
- Execute media engine RTP protection smoke.
- Execute window rotation and service perspective matrix smokes.

### C. Historical decode/export implementation

- Demux MXF using GStreamer or FFmpeg.
- Select track by embedded identity and/or verified physical TrackIndex.
- Decode/cut interval.
- Generate evidence bundle.
- Verify integrity chain.

### D. Integrated campaigns

- Fault injection.
- Progressive stress L1-L5.
- Integrated acceptance plan.
- Evidence bundle validation.

### E. External conformance

- Verify target profile and ED-137-like requirements.
- Test against real or reference equipment.
- Add profile-specific adapters only after preserving model-base invariants.

