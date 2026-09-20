# Hotfix 2.0.7

- Native runner now prepends the detected GStreamer MSVC `bin` directory to `PATH` before launching `mxf-lab.exe`.
- Added `mxf-lab selftest` to prove Windows DLL loading and required GStreamer element discovery before scale tests.
- `06-build-native.cmd` now runs the runtime self-test after compilation.
- Native scale runner captures stdout/stderr and exit codes into per-scale logs.
- Fixed PowerShell 5.1 scalar `.Count` failure by always wrapping filtered results in `@(...)`.
- Removes stale MXF files before each scale attempt and distinguishes `WRITE_FAIL`, `NO_FILE`, and `INSPECT_FAIL`.
