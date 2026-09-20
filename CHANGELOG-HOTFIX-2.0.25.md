# Hotfix 2.0.25 — Loaded next-window pre-arm

Adds a contention gate that reuses a first batch of 100 already-created current-window files, keeps all 100 handles open, drives at least 25% with PCMA-like packet writes, records JSONL logs, accesses a real SQLite WAL database, and concurrently precreates/arms another 100 next-window files.

New command:

`19-file-manager-loaded-prearm.cmd`

The gate measures same-run baseline vs loaded pre-arm delay, readiness margin, activation dispatch, packet/log/database activity, and worker health.
