# Phase 24 — Final PoC Packaging / Release Candidate

## Purpose

Phase 24 consolidates the Windows-native recording PoC into a release-candidate package. It does not claim that the system is production-ready and does not convert unexecuted gates into PASS. It creates a single operational map for the artifacts produced across the PoC phases.

The goal is to make the PoC handoff auditable:

```text
architecture decisions
  ↓
phase matrix
  ↓
operator commands
  ↓
gate list
  ↓
execution checklist
  ↓
release-candidate declaration
```

## Evidence boundaries

The release candidate package preserves the evidence semantics frozen in previous phases:

```text
closed MXF + manifest + index + hash chain = evidential source
live buffer = operational preview, not evidence
fixture = harness input, not evidence
synthetic silence = presentation convenience, not recorded audio
gap = explicit absence/interruption, not fabricated audio
```

## Release candidate status vocabulary

A package may be called `RC_READY_FOR_EXECUTION` when all files, commands, gates, and checklists are present.

It may be called `RC_VALIDATED` only after the integrated acceptance gates have actually run and passed.

```text
RC_PACKAGED
    artifacts consolidated; no execution implied

RC_READY_FOR_EXECUTION
    operator can run the campaign using the runbook and command matrix

RC_BLOCKED
    mandatory gate missing, broken, or not runnable

RC_VALIDATED
    mandatory gates executed and passed; evidence bundle created
```

`NOT_RUN` remains `NOT_RUN`.

Operator rule: NOT_RUN remains NOT_RUN in every release report.

## Included phase matrix

The release candidate references all major PoC areas:

| Area | Main phases |
| --- | --- |
| Network foundation | Phase 1 |
| MXF identity, scale and file manager | Phase 2 |
| Recorder and CWP direct recording | Phases 3–7 |
| Gateway and translated ingress | Phase 8 |
| Mono service perspective | Phase 9 |
| Media Bank / scenarios | Phase 10 |
| Temporal index | Phase 11 |
| Observability / event bus | Phase 12 |
| Historical playback and export | Phases 13–18 |
| Integrity and recovery | Phases 19–20 |
| Stress and acceptance | Phases 21–22 |
| Operator runbook | Phase 23 |
| Final packaging | Phase 24 |

## Command groups

The release package points the operator to these high-level commands:

```powershell
# Runbook completeness
.\scripts\runbook\21-operator-runbook-smoke.cmd

# Integrated acceptance aggregation
.\scripts\acceptance\20-integrated-acceptance-plan-smoke.cmd

# Integrated acceptance simulation only
.\scripts\acceptance\20-integrated-acceptance-plan-smoke.cmd -SimulatePass

# Release package completeness
.\scripts\release\22-final-poc-packaging-smoke.cmd
```

## Non-goals

Phase 24 does not:

- perform a full recorder run;
- validate real MXF decoding;
- prove ED-137 conformance;
- certify production readiness;
- replace the integrated acceptance campaign;
- convert simulated reports into evidence.

## Acceptance principle

The package is acceptable when it can clearly answer:

```text
What exists?
Where is it?
How do I run it?
What must pass?
What remains simulated?
What is evidence and what is not?
What blocks release validation?
```
