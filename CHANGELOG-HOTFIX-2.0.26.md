# Hotfix 2.0.26 — Loaded pre-arm worker startup

- Fixed current-window manifest serialization for Windows PowerShell: the 100 rows are passed to `ConvertTo-Json` through `-InputObject` so they remain one JSON array instead of being pipeline-enumerated.
- Parent process immediately re-reads and validates the manifest row count before launching the worker.
- Added staged worker startup diagnostics: `LOAD_MANIFEST`, `OPEN_CURRENT_FILES`, `SQLITE_BINDINGS`, `SQLITE_OPEN_AND_WAL`, `FIRST_DB_TRANSACTION`, `FIRST_LOG_WRITE`, `FIRST_MEDIA_WRITE`, `READY_HANDSHAKE`, `RUNNING_LOAD`.
- READY is emitted only after 100 current files are open and SQLite/WAL, one DB transaction, one JSONL event, and first media writes have succeeded.
- On pre-READY worker death, the parent reports child exit code, failure stage/reason, and stderr tail.
- No native rebuild is required. Re-run `19-file-manager-loaded-prearm.cmd`.
