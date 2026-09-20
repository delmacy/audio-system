# Multi-track audio injection lab

Purpose: inject different source audio files into independent Recorder logical tracks, then validate the resulting closed media in the frontend Recorded Track Lab.

## 1. Edit the manifest

Copy the tracked example to a machine-local manifest and edit the local copy:

```powershell
Copy-Item .\scenarios\player\multi-track-audio-injection-01.json .\scenarios\player\multi-track-audio-injection.local.json
```

Edit:

`scenarios/player/multi-track-audio-injection.local.json`

The `.local.json` file is ignored by Git, so Windows paths and local test audio do not make the repository dirty.

Each entry defines one independent RTSP/RTP recording session.

Important:
- each track must use a unique `local_rtp_port`;
- each configured Recorder route must use the correct `recorder_rtp_port`;
- `endpoint_id + service_type + service_id` defines the semantic service identity;
- `source_audio` can be WAV/MP3/etc. supported by FFmpeg;
- the runner converts it to raw G.711 A-law / PCMA, 8 kHz, mono before injection.

The sample paths are examples and may not exist on every checkout. Replace them with real local audio paths as needed.

## 2. Make sure the Recorder lab is running

Use the Recorder setup appropriate to your configured routes. The injection runner does not start or reconfigure Recorder routes automatically.

## 3. Run injection

From repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\player\Invoke-MultiTrackAudioInjection.ps1 \
  -Manifest .\scenarios\player\multi-track-audio-injection.local.json
```

The run creates:

```text
runs/audio-injection/<timestamp>/
├─ <track>.pcma
├─ <track>-stdout.txt
├─ <track>-stderr.txt
└─ injection-report.json
```

## 4. Validate in frontend

Keep the timeline API running:

```powershell
python scripts/player/timeline_api.py
```

Open the Component Catalog, Timeline tab, Recorded Track Lab, choose `Real`, then `Atualizar`.

Expected result: each injected semantic service appears as its own recorded track with its own LogicalTrackUUID and segment evidence.
