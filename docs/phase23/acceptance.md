# Phase 23 Acceptance — Operator Runbook / Deployment Notes

The phase is accepted when the package contains operator-facing material sufficient to run and interpret the PoC campaign.

## Required files

- `docs/phase23/operator-runbook-deployment-notes.md`
- `docs/phase23/acceptance.md`
- `config/runbook/operator-runbook.ini`
- `scenarios/runbook/operator-runbook-01.json`
- `scripts/runbook/21-operator-runbook-smoke.cmd`
- `scripts/runbook/Invoke-OperatorRunbookSmoke.ps1`

## Acceptance checks

1. The runbook states the CWP direct path and the gateway translated path.
2. The runbook preserves the mono service identity invariant.
3. The runbook distinguishes evidence, live preview, fixtures and simulation outputs.
4. The runbook provides a first-boot order.
5. The runbook provides a gate execution order.
6. The runbook defines report statuses without allowing unexecuted gates to become `PASS`.
7. The smoke verifies required files and core terms.
8. The smoke emits a deterministic report under `runs/runbook/`.

## Explicit non-goals

- This phase does not certify real ED-137 compliance.
- This phase does not make live buffers evidential.
- This phase does not run the full integrated acceptance campaign.
- This phase does not replace the Phase 22 acceptance aggregator.
