# RC1 execution patch — 2026-09-19

## Web Player frontend reset

- Removed the entire previous `web/player` frontend tree at the user's request. The historical playback API and recording artifacts remain available.
- `Start-WebPlayer.ps1` reports `API_ONLY` while no frontend index exists. The prior static player smokes are historical and do not validate the next interface; new frontend gates remain `NOT_RUN`.
- Reset inventory and intended next interface are recorded in `docs/rc1/web-player-frontend-reset-2026-09-19.md`.

## Web Player V2 visual interface

- Created a new React/TypeScript/Vite frontend with shadcn/ui, Radix, Lucide and Zustand in `web/player-app`; its built output is served from `web/player`.
- Added a desktop timeline following the supplied light visual reference: CWP/TEL/RADIO groups in the main canvas, individual and group checkboxes, activity bars, draggable playhead, IN/OUT span, shading across tracks, zoom, overview, fixed transport, and a compact navigation rail.
- Marked the mock timeline and moving clock as a demonstration without recorded evidence. Export remains disabled until the real historical audio chain is connected.
- Replaced the Phase 15 shell smoke with a scoped V2 build gate. The Phase 16 historical interaction modes and Phase 17 live frontend gates now report `BLOCKED` instead of passing against removed files.
- Browser, build, gate results and screenshot are recorded in `docs/rc1/web-player-v2-visual-execution.md`.

The Windows RC1 run is recorded under `runs/rc1/rc1-20260919-134242/`. Every attempt has a command, timestamps, exit code, and captured output. The gate verdicts and limitations are in `RC1-execution-report.md` in that directory.

## Corrections

- Added the literal mono and `NOT_RUN` operator wording required by the closure and packaging checks.
- Fixed the PowerShell acceptance report parser so the default invocation produces a blocked report with 21 `NOT_RUN` gates.
- Moved phase 17–19 script-root resolution into the script body. Their reports now identify synthetic fixture scope; the fault fixture records zero faults actually injected and the stress fixture records zero load executed. Replaced the integrity smoke hash call with .NET SHA-256 for the `.cmd` execution path.
- Set the GStreamer MSVC property-sheet root during Recorder build and made GStreamer runtime DLLs available to Recorder smoke child processes.
- Moved the large RecorderHost state out of the main-thread stack, fixing the selftest stack overflow.
- Replaced use of PowerShell's read-only `$Host` variable in Recorder smoke scripts.
- Updated Recorder summary parsers for the metrics now emitted between `sequence_gap_packets` and `mux_bytes`.
- Corrected the RTP sequence-gap count: a packet received at 5011 when 5010 is expected means one missing packet.
- Reused the existing UUIDv5/UUIDv7 helpers in the mono service identity function.
- Strengthened the mono service matrix gate to verify expected packet counts, finalized files, and one mono audio stream per file. Its report explicitly says embedded LT/TI verification was not performed by that gate.
- Marked the older phase 5 RX/TX routing fixture as a legacy routing mechanics test. It does not validate the frozen mono service model.

No architectural decision was changed. No dependency installation was needed for the executed gates.

## Execution continuation

- Executed the Windows network smoke: UDP 10/10 in both directions with a dumpcap capture. Removed the interactive `pause` from its `.cmd` wrapper.
- Reran File Manager loaded pre-arm: 100/100 next files ready before T0−250 ms and activation within the 250 ms budget.
- Replaced Phase 11 SQLite fixture smoke with ingestion of two real closed Phase 7 MXFs, four media intervals, three explicit gaps, 46 audit events and an idempotent replay check.
- Added Recorder audit payload byte offsets and propagated them through SQLite and historical playback. Replaced the default segment export gate with actual FFmpeg demux/decode of selected MXF tracks and hash/embedded LT/TI checks. Full-interval export passed; arbitrary clipping remains open.
- Replaced evidence bundle and integrity fixture gates with real MXF/WAV/source-map hash verification. Recorder-generated per-file manifests remain absent, so the full evidential chain stays `BLOCKED`.
- Corrected Player fixture path control characters and interaction mode check. Player gates remain static and are `BLOCKED` for integrated real playback/live tap.
- Added PCMA tone input at 2500 Hz and 3500 Hz on two direct CWP routes. Decoded closed MXFs showed the expected tone in each embedded LT/TI track with high expected/other-frequency power ratios.
- Executed six RTP impairment classes against the Recorder. Gate 18 now returns `BLOCKED` because five recovery scenarios are still `NOT_RUN`.
- Executed direct mono load with 1, 5, 10, 30 and 50 concurrent services. Gate 19 now returns `BLOCKED` because the Gateway mix, fault overlays and long soak are `NOT_RUN`.
- Added the RC1 evidence aggregator behind gate 20. It reports `BLOCKED`, with 12 of 19 mandatory gates passing in their recorded scope. Earlier synthetic aggregator output remains historical only.

See `runs/rc1/rc1-20260919-134242/RC1-execution-report.md` for commands, outcomes, fixes and open risks.

## Operational launch continuation

- Reworked the Web Player into a dark ATC investigation console with a logical service tree, synchronized UTC timeline rows, explicit gap/event markers, technical detail panel, integrity status, and decoded waveform monitor.
- Historical MXF playback is automatic after selecting an indexed service: the browser receives PCM/WAV because browser engines do not decode MXF directly, while the server verifies the closed MXF hash and embedded LT/TI before serving it. The UI labels this as `Reproduzir MXF fechado` and keeps the missing Recorder manifest visible.
- Added a persistent demux cache under `runs/web-player-cache`, keyed by source MXF SHA-256 and physical track identity (or plan hash and mode for historical export). The API reports cache hits without weakening the LT/TI or hash checks.
- Set cache retention to seven days with startup pruning and added `scripts/player/Warm-WebPlayerCache.ps1` to prewarm all closed MXFs in the observed catalog. Added a multi-track `/api/mix` path and timeline selection controls; mixes remain analysis audio and are explicitly not evidence bundles.
- Simplified the live Player view to services/CWP at left, timeline first, and player below the lanes; the detail and occurrence panels are hidden in this operator view. Added `/api/live` polling with an explicit live-preview status. A selected historical track keeps its UTC window and lane fixed while live status is refreshed, so the selected timeline does not roll underneath the operator.
- Stopped the previous Recorder/Player processes, removed the old unreferenced MXF/partial/lock corpus, regenerated the indexed Phase 7 MXFs and SQLite index, then exercised six-service CWP routing (`PASS`) and a live CWP PCMA transmission (`PASS`, 150 packets, 3 seconds media). The live buffer remains unavailable and is not evidence.

- Added `scripts/recorder/Start-RecorderLab.ps1` for a native direct CWP RTSP/RTP listener with one mono service route and isolated run artifacts. The launched process reached READY and answered RTSP OPTIONS with 200; its current `.partial` is not evidence.
- Added `scripts/player/serve_player.py` and `Start-WebPlayer.ps1`. The local HTTP API reads the latest SQLite index, invokes the real historical plan and closed-MXF export scripts, and serves the resulting WAV to the browser.
- Replaced the served Player fixture path with the operational historical UI. Browser verification loaded four media intervals from two closed MXFs, generated a 19,244-byte WAV, displayed its audio control, and switched to ONLY ACTIVITY. The live fixture now says `SIMULADO`.
- Fixed a browser overflow caused by the export manifest and updated static Player checks for the operational entrypoint. Launch scope and limitations are in `docs/rc1/operational-launch.md` and `runs/operational-stack/current-launch-report.json`.
## 2026-09-19 — Live stack and timeline needle

- Added `scripts/recorder/Start-LiveRecorderStack.ps1` to keep the Windows Recorder stack available while each RTSP session closes and commits its MXF; it relaunches the PoC host between clean session teardowns.
- Added `scripts/cwp/Start-LiveCwpSimulator.ps1` as the continuous direct CWP simulator loop for the configured mono service route.
- Web Player main view now keeps the left service/CWP accordion visible beside the service timeline, with an Adobe Audition-style red time needle driven by the verified extraction audio; clicking the selected lane seeks the extraction audio.
- Extraction remains below the timeline and is labeled `Extrair áudio verificado`; the live indicator remains preview-only and does not update the selected historical timeline.
- Reworked the visual shell toward the supplied AudioReview reference: light canvas, compact navigation, CWP accordion groups, service lanes, and a compact extraction transport.
- Catalog accordion groups are now keyed by endpoint/CWP so each expanded group lists its available logical service tracks.
- Added an explicit draggable-looking IN/OUT span band and persistent timeline needle position for the selected plan, including before the extracted WAV metadata finishes loading.
- Vendored `wavesurfer.js` 7.10.0 and `peaks.js` 4.0.0 under `web/player/vendor` as the waveform, zoom, overview, marker and region implementation base.
