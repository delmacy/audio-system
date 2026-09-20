# Phase 14 Acceptance — Playback Decode / Segment Export

Deferred integrated gate command:

```powershell
.\scripts\playback\12-playback-segment-export-smoke.cmd
```

The gate should pass when:

1. A Phase 13 playback plan is generated or supplied.
2. The exporter resolves media items by `LogicalTrackUUID`, `FileId`, `TrackInstanceUUID` and interval.
3. The output manifest lists every media source and every gap.
4. The output audio is mono, 8 kHz WAV in the harness.
5. `only_audio` mode excludes gaps from audio duration while retaining UTC mapping.
6. `continuous` mode may insert gap silence only as explicit synthetic presentation material.
7. No gap is represented as recorded media.
8. Distinct physical track instances remain visible in the manifest.
9. The output bundle contains `export.wav`, `export-manifest.json`, `playback-plan.json`, `source-map.csv` and `events.jsonl`.
10. The smoke summary reports `PLAYBACK SEGMENT EXPORT: PASS`.
