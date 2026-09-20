# File Manager pre-arm / window-boundary capacity

## Purpose

The recording boundary must not depend on creating many files exactly at the boundary timestamp. The File Manager prepares the next logical window in advance.

For a window beginning at `T0`:

1. At `T0 - precreate_lead_ms`, create every required `.mxf.partial` path.
2. Open and retain the manager-owned write handle for every file.
3. Create the operational lock metadata and mark the file `ARMED`.
4. Before `T0 - ready_deadline_ms_before_window`, require a 100% READY barrier for required files.
5. At `T0`, perform no `CreateFile/CreateNew`. Only release the already-open writers into the new logical window.
6. If the barrier is not complete, production policy is `BOUNDARY_SPILL_REQUIRED`: keep the previous window writer(s) receiving required media until replacement writers are available. Never trade a clean hour boundary for an unreported media gap.

## Time semantics

Physical creation time and logical recording time are separate facts.

- `file_created_utc`: when the physical file/handle was created.
- `file_armed_utc`: when the file became ready for activation.
- `recording_window_start_utc`: the logical start of the recording interval represented by the file.
- `recording_window_end_utc`: the planned logical end.
- `segment_sequence`: deterministic rollover order within the same logical window.
- `window_activated_utc`: when the already-open writer was released at/after T0.

Canonical historical ordering is by logical time, not directory enumeration or filesystem creation time:

`recording_window_start_utc, segment_sequence, first_media_utc`

`PackageCreationDate` in the eventual MXF remains audit evidence of physical creation and must not be overloaded to mean the logical window start.

## Capacity gate

Run:

`17-file-manager-prearm-capacity.cmd`

Default gate:

- 100 required files.
- 10000 ms precreate lead for the required profile.
- 250 ms READY deadline before T0.
- 250 ms maximum activation-dispatch span.
- manager-owned open handles with read sharing only (no second writer and no delete sharing).
- representative delete/rename probes while ARMED.
- zero physical file creation at or after T0.

The capacity probe writes a tiny activation marker, not MXF essence. Files are renamed to `.capacity-probe.closed` after the test so they cannot be confused with valid MXF output. Integration of the manager-owned handle with the actual MXF byte writer belongs to the following storage/durability work.

## Acceptance

PASS requires:

- `ready_at_deadline == file_count`;
- `created_after_window_start_count == 0`;
- all representative delete/rename guards hold;
- all 100 pre-opened handles accept activation;
- activation-dispatch span is within budget.

If READY is incomplete, the gate emits `BOUNDARY_SPILL_REQUIRED` and fails. It must never create the missing required file on the boundary path and silently omit media while doing so.


## Controlled 3 s vs 10 s comparison

Run `18-file-manager-prearm-compare.cmd`. It executes the repaired gate twice with identical logic: first with a 3000 ms lead (baseline) and then with a 10000 ms lead (required profile). The generated comparison JSON records readiness, batch precreate+arm duration, minimum/P95 arming margin, activation dispatch span, and failure stage for each trial. The 3 s result is observational; the 10 s profile is the required PASS condition.
