# RC1 local operational launch

This run starts the native Recorder lab listener and the historical Web Player on Windows. Current process IDs and checks are in `runs/operational-stack/current-launch-report.json`.

## Start

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\recorder\Start-RecorderLab.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\player\Start-WebPlayer.ps1
```

Open `http://127.0.0.1:8765/`. The player lists services in the latest executed SQLite temporal index. Selecting an indexed service generates a plan and automatically asks the server to validate the closed MXF hash and embedded LT/TI, demux the selected physical track, and make an 8 kHz mono WAV available to the browser. Browsers do not decode MXF directly; this conversion is transparent to the operator and the waveform is drawn from the decoded bytes. Demux results are cached by MXF SHA-256 plus track identity; repeated listens reuse the verified cache. Cache files are retained for seven days and old entries are pruned when the player starts. To prewarm all closed MXFs observed in the catalog, run `.scripts\player\Warm-WebPlayerCache.ps1`.

The timeline can select multiple indexed logical services and request a playback mix. Each source plan is validated and decoded first; the mixed WAV is a convenience for analysis and listening, not a replacement for source tracks or an evidential bundle. The current RC1 index contains one indexed logical service, so the mix control remains disabled until another service is indexed.

The Recorder lab listener binds `10.20.0.10:8554` and arms one direct CWP route, `/record/CWP-LAB-01/radio-lab-121500`, on RTP port 20500. Its current file is `.mxf.partial` until a client completes the RTSP/RTP session and the Recorder closes it. The player only queries previously closed, indexed MXFs. It does not read the current partial file.

## Scope

The historical player, SQLite lookup, real MXF decode and WAV HTTP delivery were exercised in a browser. The operational Gateway is still a scenario harness, not a resident daemon. Continuous index ingestion, Recorder live tap and authoritative Recorder-generated file manifests are not available. The live page is labelled `SIMULADO` and is not evidence. The RC1 integrated acceptance verdict remains `BLOCKED`.

Do not kill the Recorder process while a file is open unless testing crash recovery; that would leave a partial recording requiring inspection. Its lab process is one-shot: it exits after the configured session closes or the configured timeout is reached. Use a new run directory for each launch.
