# Phase 10 — Media Bank Builder + Conversation Scenario Generator

## Status

`MATERIALIZED` — prepared for local Windows execution once the user has audio assets.

This phase intentionally does not require target audio files to exist. It establishes the repeatable workflow for ingesting raw audio, cutting candidate clips, reviewing them, and generating realistic mono-service conversation timelines for later Recorder/Player integrated tests.

## Architectural rule

Phase 9 remains frozen:

- one recordable service = one RTP/UDP flow;
- one RTP/UDP flow = one mono PCMA audio stream;
- one service = one `LogicalTrackUUID`;
- no default RX/TX split in Recorder/MXF;
- no artificial stereo;
- no duplicated media for perspective.

Phase 10 may use folders such as `controller`, `pilot`, `ring`, `busy`, `conversation`, or even legacy `tx/rx` folders inside the media bank. Those labels describe the **source role used by the simulator**, not Recorder track direction.

## Media bank layout

Recommended minimal layout:

```text
media-bank/
├── raw/
│   ├── radio-mixed/
│   └── telephone-mixed/
├── radio/
│   ├── controller/
│   ├── pilot/
│   └── unknown/
└── telephone/
    ├── tones/
    │   ├── ring/
    │   └── busy/
    └── conversations/
```

If the user prefers TX/RX during collection, keep it as staging only:

```text
media-bank/raw/radio-controller-tx/
media-bank/raw/radio-pilot-rx/
```

The generated Recorder identity still uses:

```text
identity-v1|service_type=radio|service_id=121500|endpoint_id=cwp-a01|media_flow=mono
```

## Workflow

1. Initialize folders.
2. Put raw audio files into `media-bank/raw/...`.
3. Detect candidate speech segments using FFmpeg `silencedetect`.
4. Cut segments into normalized mono WAV clips.
5. Optionally review/edit the manifest CSV.
6. Generate a conversation scenario manifest.
7. Later, a simulator will emit RTP and signaling events from that manifest.

## Scripts

```powershell
scripts\media-bank\20-media-bank-init.cmd
scripts\media-bank\21-audio-detect-segments.cmd
scripts\media-bank\22-audio-cut-manifest.cmd
scripts\media-bank\23-conversation-generate.cmd
scripts\media-bank\24-media-bank-smoke.cmd
```

## FFmpeg dependency

The scripts expect FFmpeg at either:

```text
C:\ffmpeg\bin\ffmpeg.exe
```

or in `%PATH%`.

This matches the existing PoC assumption already used in earlier phases.

## Detection model

`21-audio-detect-segments.cmd` uses FFmpeg silence detection. It does not need transcription. It creates a CSV of candidate segments:

```csv
clip_id,source_file,start_sec,end_sec,duration_ms,speaker_hint,confidence,review_status,output_path,notes
```

`speaker_hint` is conservative:

- if the input folder or filename contains `controller`, it suggests `controller`;
- if it contains `pilot`, it suggests `pilot`;
- if it contains `ring`, `busy`, or `telephone`, it suggests the respective telephone role;
- otherwise it uses `unknown`.

No script claims certainty. Unknown clips remain usable by the generator or can be manually moved later.

## Cutting model

`22-audio-cut-manifest.cmd` reads the CSV and writes clips with:

- mono audio;
- 8000 Hz sample rate;
- WAV PCM output for staging;
- optional normalization filter;
- deterministic clip filenames.

A later RTP emitter can transcode/payload as PCMA, or an optional future builder can create `.alaw` assets.

## Conversation generator model

`23-conversation-generate.cmd` does not need perfect semantic classification. It alternates roles according to a simple probabilistic pattern:

```text
pilot → pause → controller → pause → pilot → longer pause → controller
```

For telephone:

```text
ring → answer → side_a → pause → side_b → pause → release
```

The output is a scenario manifest, not a final audio mix:

```json
{
  "schema": "recorder-poc.conversation-scenario.v1",
  "service_id": "121500",
  "media_flow": "mono",
  "events": [
    { "t_ms": 0, "event": "SQU_ON", "speaker": "pilot", "asset": "..." },
    { "t_ms": 2100, "event": "SQU_OFF" }
  ]
}
```

The Recorder still receives one mono RTP flow per service.

## Acceptance criteria

Phase 10 is considered materially ready when:

- folder initialization is deterministic;
- segment detection emits a CSV even when no audio exists;
- cutter refuses missing files clearly;
- generator can produce a placeholder scenario from existing clips;
- scenario manifest contains service, media_flow=mono, asset references, and timeline events;
- no RX/TX Recorder track split is reintroduced.
