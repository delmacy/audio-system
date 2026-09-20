# Phase 6 — 6.0.0

## Added

- Minimal Media Engine boundary in `recorder-host.exe`.
- RTP parser/classifier counters for malformed packets, unsupported payload types, duplicates, out-of-order packets, inferred sequence gaps, and timestamp discontinuities.
- Safe drop behavior for duplicate/late/malformed/wrong-payload RTP.
- Audit events for RTP media-quality anomalies.
- Future smoke gate `scripts\recorder\05-media-engine-smoke.cmd`.
- Controlled impairment simulator `scripts\cwp\Invoke-MediaEngineImpairmentSimulator.ps1`.
- `config\recorder\media-engine.ini` and `scenarios\media-engine-impairment-01.ini`.

## Preserved

- Phase 3 single-CWP recorder smoke contract.
- Phase 4 persistent radio session contract.
- Phase 5 multi-session routing contract.
- File Manager complete/validated state from Phase 2.

## Notes

This phase is materialized but not target-validated in the current turn. It should be compiled and executed in the later integrated Windows/GStreamer campaign.
