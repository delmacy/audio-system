# Hotfix 2.0.27 — Loaded Pre-arm Manifest Contract

Fixes `OPEN_CURRENT_FILES` failures where a manifest path could arrive at `System.IO.File.Open()` in an unsupported shape.

## Changes
- Replaces the loose JSON-array manifest with `recorder-poc.current-window-file-manifest.v2` (`schema`, `file_count`, `files[]`).
- Parent validates all 100 paths after JSON round-trip using `GetFullPath` and `Test-Path` before starting the load worker.
- Worker explicitly extracts and validates one scalar `partial_path` per row before calling `File.Open`.
- Worker rejects arrays, empty strings, embedded quote characters, non-rooted paths and missing files.
- Any open failure now reports row index, slot, raw value/type, normalized path and the original exception.
- No changes to the pre-arm timing model, media workload, SQLite workload or activation budget.
