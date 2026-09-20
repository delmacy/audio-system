# Hotfix 2.0.23 — deterministic 3s/10s comparison

- comparison trials now use explicit unique RunId directories; no newest-directory guessing;
- partial/FAIL reports are tolerated under Set-StrictMode without missing-property crashes;
- comparison always preserves result, process exit code, failure_stage, failure_reason and report path;
- standalone capacity runs use millisecond+PID run IDs to avoid directory collisions;
- 10 second pre-arm profile remains the default.

