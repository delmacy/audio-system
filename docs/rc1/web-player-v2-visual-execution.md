# Web Player V2 visual execution — 2026-09-19

The frontend was rebuilt from a clean directory in `web/player-app`. The Vite build publishes to `web/player`; the historical playback Python API remains separate.

## Executed

- `npm run build`: PASS. TypeScript and Vite compiled the React frontend.
- `npm run lint`: completed with one warning in the generated shadcn button component; no application code diagnostics.
- `scripts/player/13-web-player-shell-smoke.cmd`: PASS for the React visual shell and mock timeline only. Report: `runs/web-player-shell/web-player-v2-shell-smoke-result.json`.
- Desktop browser inspection at 1672 × 940: six CWP/TEL/RADIO groups, activity bars, red playhead, external shading across rows, overview, fixed transport. Screenshot: `docs/rc1/web-player-v2-desktop.png`.
- Browser interactions exercised: collapse CWP group, toggle its group checkbox, increase zoom from 100% to 125%, start/pause the demonstration clock, open the export panel. The export action was disabled. Browser console ended with zero errors and zero warnings.
- The existing web server returned the built page and `Start-WebPlayer.ps1` reported `READY`.

## Gate boundary

- `scripts/player/14-player-interaction-modes-smoke.cmd`: BLOCKED. Real historical audio modes are not connected to the new frontend. Report: `runs/player-interaction-modes/player-v2-interaction-report.json`.
- `scripts/player/15-live-player-branch-smoke.cmd`: BLOCKED. The new frontend has no live tap connection. Report: `runs/live-player-branch/player-v2-live-report.json`.
- All visible service bars and the moving transport clock are demonstration data. They are not evidence and do not produce audio. No MXF decode, source map, mix, or Evidence Bundle was claimed by this UI gate.

## Next integration

Replace the demo `groups → tracks → segments` source with catalog and temporal-index playback plans, maintaining one mono logical service per track. Bind the selected span and checked tracks to verified closed-MXF decode and export. A separate live preview branch may be added with an explicit non-evidence label.
