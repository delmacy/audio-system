# Recorder PoC — Phase 25 / 25.0.0

Status: MATERIALIZED.

This package adds closure, open risks, next implementation backlog, and root agent handoff files (`AGENTS.md` and `CODEX.md`).

Run the static closure smoke on Windows with:

```powershell
.\scripts\closure\23-closure-backlog-smoke.cmd
```

This smoke validates static handoff completeness only. It does not execute recorder, MXF decode, or integrated acceptance gates.

---

# Recorder PoC — Phase 24 / 24.0.0

Windows-native recorder PoC package through Phase 24.

Current top-level status: `RC_PACKAGED`.

This package consolidates all materialized phases and adds the final release-candidate packaging layer. It does not claim production readiness and does not mark unexecuted gates as passed.

Key command:

```powershell
.\scripts\release\22-final-poc-packaging-smoke.cmd
```

Integrated acceptance remains a separate campaign:

```powershell
.\scripts\acceptance\20-integrated-acceptance-plan-smoke.cmd
```

Evidence boundaries remain unchanged:

- live buffer is not evidence;
- fixture is not evidence;
- synthetic silence is not recorded audio;
- explicit gap is not generated evidence;
- closed MXF + manifest + index + hashes form the evidential chain.
