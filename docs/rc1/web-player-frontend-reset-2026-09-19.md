# Web Player frontend reset — 2026-09-19

The previous Web Player frontend was removed at the user's request. The removed `web/player` tree contained `index.html`, `live.html`, application CSS/JavaScript, frontend fixtures, and previously downloaded vendor packages (123 files, 6,766,295 bytes at inventory time). No new interface was installed in this step.

The Python historical playback API and its MXF/index/cache code remain under `scripts/player`. The active API answered `/health` with HTTP 200; `/` answered HTTP 404 after the reset. `Start-WebPlayer.ps1` now reports `API_ONLY` while no frontend index exists.

The former Phase 15–17 static player smokes refer to removed files. Their earlier reports remain historical records, but they are not validation of the next frontend. New frontend gates are `NOT_RUN`.

The next implementation should follow the supplied visual reference and interface description: a light timeline editor with a navigation sidebar, CWP/TEL/RADIO groups inside the main timeline, service checkboxes, proportional activity bars, a red playhead across rows, a manipulable IN/OUT span, external shading across all tracks, overview, and fixed transport. Data mocked for visual interaction must be identified as simulation and never as recorded evidence. Preserve one logical mono service per track and the existing evidence boundaries.
