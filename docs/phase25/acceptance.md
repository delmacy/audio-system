# Phase 25 Acceptance

Phase 25 passes if the closure package contains:

- `AGENTS.md` with full project scope and invariants.
- `CODEX.md` pointing to `AGENTS.md`.
- Phase 25 closure documentation.
- Open risks section.
- Next implementation backlog.
- Explicit `NOT_RUN != PASS` rule.
- Explicit evidence boundaries:
  - live buffer is not evidence,
  - fixture is not evidence,
  - synthetic silence is not recorded audio.
- Explicit architecture boundaries:
  - CWP direct to Recorder,
  - Gateway only for SIP/telephony and physical/legacy radio adapters,
  - one mono flow per service.

The Phase 25 smoke checks static completeness only. It does not validate the recorder, MXF decode, ED-137 conformance, or integrated campaign execution.
