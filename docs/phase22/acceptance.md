# Phase 22 Acceptance Criteria

Phase 22 is accepted when the integrated acceptance harness can produce a coherent campaign report without inventing PASS results.

## Required checks

1. The integrated campaign file exists.
2. The campaign includes gates from Phase 1 through Phase 21.
3. Each gate has a deterministic id, script reference, required flag and expected evidence path.
4. Required gates cannot be silently skipped.
5. Optional capacity gates can be `NOT_RUN` without failing the whole campaign.
6. Final verdict is derived from gate statuses, not manually asserted.
7. Frozen invariants are present in the report:
   - CWP direct to Recorder.
   - Gateway only for translated ingress.
   - mono service identity.
   - LogicalTrackUUID stable logical identity.
   - TrackInstanceUUID physical occurrence identity.
   - live buffer not evidence.
8. Evidence-critical failures always force final `FAIL`.
9. Missing required evidence forces `BLOCKED` or `FAIL`.
10. The report includes explicit `NOT_RUN` or `BLOCKED` where a gate was not executed.

## Smoke acceptance

The deterministic smoke script may simulate gate results. That simulation is acceptable only for testing the aggregation logic. It must label itself as simulated and must not be confused with a real acceptance run.

Smoke output must include:

```text
integrated-acceptance-report.json
integrated-acceptance-report.md
integrated-acceptance-summary.csv
```

## Failure classes

```text
FAIL_INTEGRITY
FAIL_CROSS_CONTAMINATION
FAIL_SILENT_LOSS
FAIL_EVIDENCE_MISMATCH
FAIL_RUNNER_ERROR
BLOCKED_MISSING_PREREQ
BLOCKED_NOT_EXECUTED
```
