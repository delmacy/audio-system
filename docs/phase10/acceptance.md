# Phase 10 Acceptance — Media Bank Builder

## Deferred target acceptance

This phase is a tooling preparation phase. It is not target-validated until real or synthetic user-provided audio is processed locally.

## Future gate

Command:

```powershell
scripts\media-bank\24-media-bank-smoke.cmd
```

Expected proof:

- media-bank folders exist;
- FFmpeg is discoverable or missing dependency is reported clearly;
- raw audio discovery works;
- `clips-manifest.csv` is created;
- cut clips are mono 8 kHz WAV when audio exists;
- `conversation-scenario.json` is created from clips or placeholder clips;
- scenario uses `media_flow=mono`;
- no generated Recorder route requires `RX/TX` split;
- role labels are simulator metadata only.
