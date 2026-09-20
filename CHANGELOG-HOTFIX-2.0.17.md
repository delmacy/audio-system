# Hotfix 2.0.17 — Embedded Track Identity validator

## Fix

The MXF identity was correctly persisted in `TrackName`, but the 2.0.16 PowerShell gate compared the expected semantic name against the escaped output of `gst_structure_to_string()`.

2.0.17 normalizes the GStreamer structure serialization escapes before checking:

- DisplayName
- LogicalTrackUUID (`LT=`)
- TrackInstanceUUID (`TI=`)

The raw reader stdout/stderr are retained as evidence files. Known stock `mxfdemux` teardown diagnostics (`finalized while still in-construction`) are counted and reported separately; they do not cause identity validation to fail.

No plugin rebuild or `mxf-lab` rebuild is required.
