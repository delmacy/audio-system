# File Manager loaded pre-arm gate

This gate measures next-window pre-arm while the current window is under a synthetic recorder workload.

## Workload

- 100 current-window files exist before the load begins.
- All 100 current files are held open by the load worker.
- At least 25% (default: 25 files) receive PCMA-like 20 ms payloads: 160 bytes every 20 ms per active file.
- Runtime JSONL logging runs concurrently.
- A real SQLite database (`winsqlite3.dll`) runs in WAL mode and receives batched telemetry transactions concurrently.
- While that workload is active, the File Manager creates and arms 100 next-window files.
- At the logical boundary T0, the already-open next-window writers are activated; no file creation is allowed on the boundary path.

The probe files are capacity-test artifacts, not valid MXF essence files. The purpose of this gate is storage/handle/log/database contention and boundary latency; MXF validity is proven by the separate MXF gates.

## Acceptance

- 100/100 next files armed before T0 - 250 ms using the configured lead time (default 3000 ms).
- No next file created at or after T0.
- Audio-like writes, logs, SQLite transactions and SQLite rows all advance during the loaded pre-arm interval.
- Activation dispatch remains <= 250 ms.
- Worker exits PASS.

The report compares the same-run unloaded baseline against loaded pre-arm and records absolute and percentage delay.
