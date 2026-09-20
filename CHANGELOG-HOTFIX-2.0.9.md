# Hotfix 2.0.9

- Fixes native MXF inspect hangs.
- `fakesink` now uses `sync=false` and `async=false`, so inspection never replays media on wall-clock time.
- Native inspect has an internal timeout (`--timeout-ms`).
- PowerShell native process capture now reads stdout/stderr asynchronously and supports external timeouts.
- Scale runner uses bounded timeouts: 15s (100 tracks), 30s (500), 60s (1000) for inspect.
- A timeout is reported as exit code 124 instead of freezing the terminal.
