# Phase 24 Acceptance

Phase 24 passes its packaging gate when the repository contains a complete release-candidate index and no wording claims successful execution of gates that were not run.

## Required files

- `docs/phase24/final-poc-packaging-release-candidate.md`
- `docs/phase24/acceptance.md`
- `config/release/final-poc-packaging.ini`
- `scenarios/release/final-poc-packaging-01.json`
- `scripts/release/22-final-poc-packaging-smoke.cmd`
- `scripts/release/Invoke-FinalPocPackagingSmoke.ps1`
- `CHANGELOG-PHASE24-24.0.0.md`

## Required checks

The smoke script must verify:

1. Phase 24 documentation exists.
2. Release configuration exists.
3. Scenario manifest exists.
4. Runbook command exists.
5. Integrated acceptance command exists.
6. Stress runner command exists.
7. Integrity manifest chain command exists.
8. Export evidence bundle command exists.
9. Critical evidence disclaimers are present.
10. `NOT_RUN` is not treated as `PASS`.

## Forbidden claims

The Phase 24 package must not claim:

- production readiness;
- target standard conformance;
- integrated acceptance PASS without execution;
- live buffer as evidence;
- synthetic silence as recorded evidence;
- fixtures as recorded evidence.
