# Hotfix 2.0.21 — scalar temporal arithmetic for File Manager pre-arm gate

- Replaces direct `DateTime` subtraction with a scalar-checked tick calculation.
- Adds `Get-SingleUtcDateTime` invariant checking so accidental PowerShell arrays cannot silently enter timing math.
- Uses local scalar `armedUtc` values while creating each file.
- Adds `failure_stage` and a `GATE_EXCEPTION` event with script stack trace.
- Reuses the measured batch duration in the report instead of recalculating it from object properties.
- No changes to MXF writer, identity plugin, or pre-arm ownership/lock design.
