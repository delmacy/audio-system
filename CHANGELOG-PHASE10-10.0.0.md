# CHANGELOG — Phase 10 / 10.0.0

## Media Bank Builder + Conversation Scenario Generator

This phase adds tooling for building the audio bank used by future radio, telephone, CWP, CWP-to-CWP, CWP-to-phone, and CWP-to-radio simulation scenarios.

## Added

- `docs/phase10/media-bank-builder.md`
- `docs/phase10/acceptance.md`
- `config/media-bank/media-bank.ini`
- `scenarios/media-bank-builder-01.ini`
- `scripts/media-bank/20-media-bank-init.cmd`
- `scripts/media-bank/21-audio-detect-segments.cmd`
- `scripts/media-bank/22-audio-cut-manifest.cmd`
- `scripts/media-bank/23-conversation-generate.cmd`
- `scripts/media-bank/24-media-bank-smoke.cmd`
- `scripts/media-bank/Common-MediaBank.ps1`
- `scripts/media-bank/Initialize-MediaBank.ps1`
- `scripts/media-bank/Invoke-AudioDetectSegments.ps1`
- `scripts/media-bank/Invoke-AudioCutManifest.ps1`
- `scripts/media-bank/Invoke-ConversationGenerate.ps1`
- `scripts/media-bank/Invoke-MediaBankSmoke.ps1`
- `media-bank/` source and output folder skeleton.

## Key rule

TX/RX or role folders inside the media bank are **simulator source metadata only**. The Recorder/MXF model remains:

```text
one service = one mono RTP flow = one LogicalTrackUUID = one MXF track
```

No default RX/TX track split, no stereo, and no media duplication were reintroduced.

## Dependencies

The cut/detect scripts expect FFmpeg at `C:\ffmpeg\bin\ffmpeg.exe` or in `%PATH%`.

## Deferred

- real user-provided audio processing;
- optional transcription/diarization;
- manual review tooling beyond CSV manifests;
- RTP emission from generated conversation manifests.
