# Phase 3 — 3.0.0

Introduces the first persistent Recorder vertical slice after completion of the MXF/File-Manager foundation.

## Added

- `src/recorder-host/recorder_host.c`
- `src/recorder-host/storage_writer.c/.h`
- `src/recorder-host/recorder-host.vcxproj`
- Recorder build script and command wrapper.
- One-CWP RTSP/RTP simulator.
- One-CWP end-to-end smoke orchestrator.
- Minimal Recorder session contract.
- Phase 3 architecture and acceptance docs.

## Architectural decisions

- GStreamer does not own the file handle: `mxfidmux -> appsink -> Win32 StorageWriter`.
- Recorder retains the proven `.partial`/`.lock` lifecycle and delete/rename protection model.
- File Manager is recorded as complete/target-validated; endurance, crash, durability and recovery are deferred to integrated system acceptance rather than treated as File-Manager implementation gaps.
