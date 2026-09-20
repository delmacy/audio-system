# Hotfix 2.0.22 — 10-second pre-arm tolerance and controlled comparison

- Changes the default `PrecreateLeadMs` from 3000 ms to 10000 ms.
- Removes the remaining variable binary-subtraction paths from the File Manager timing gate; elapsed time now uses scalar-validated `DateTime.Subtract()` or addition with negative scalar constants.
- Prints `failure_stage` on gate failure.
- Adds `Invoke-FileManagerPrearmComparison.ps1` and `18-file-manager-prearm-compare.cmd`.
- The comparison gate runs the repaired implementation twice, at 3000 ms and 10000 ms, and emits one JSON summary with batch time, readiness, minimum/P95 arming margin, activation dispatch time, and failure stage.
- The 10-second profile is the required PASS profile; the 3-second profile is retained only as an empirical baseline.
- No changes to MXF identity, custom muxer, media format, or logical-window semantics.
