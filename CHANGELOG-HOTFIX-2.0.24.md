# Hotfix 2.0.24 — isolate child-process output from trial objects

- fixes the root cause of `PropertyNotFoundStrict` in the 3s-vs-10s comparator;
- child `powershell.exe` stdout/stderr is now captured locally and rendered with `Write-Host`, so it cannot escape `Invoke-Trial`;
- `Invoke-Trial` now returns exactly one `PSCustomObject`, never `Object[]` composed of console lines plus the result object;
- comparison metrics are read exclusively through safe optional-property helpers;
- no direct `$short.<optional>` / `$long.<optional>` / `$trial.<optional>` accesses remain;
- comparison report schema bumped to `recorder-poc.file-manager-prearm-comparison.v3`;
- capacity gate behavior and the 10,000 ms default lead are unchanged.
