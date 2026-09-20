# AudioReview timeline frontend

React 19 + TypeScript + Vite. The production build is written to `../player` and served by `scripts/player/serve_player.py` at `http://127.0.0.1:8765/`.

```powershell
cd web\player-app
npm install
npm run build
```

The timeline loads `/api/timeline`. Its media intervals come from the SQLite temporal index for closed MXFs and from `MEDIA_START`/`MEDIA_END` audit pairs in operational Recorder runs whose MXF was closed and committed. Each group is an observed endpoint/CWP, each row is one mono LogicalTrackUUID. Dates and times are shown in UTC−03:00; the Configurações panel selects the date and two-hour start time. An empty date/window is shown as empty, without fixture fallback.

Select exactly one track and press Play to request `/api/preview` for the MXF at or after the needle. The server validates the closed file, PCMA mono stream, and embedded LT/TI before returning cached WAV. This transport previews one physical MXF occurrence at a time; its needle follows the decoded clip approximately. It does not yet play continuously across files or mix tracks.

Unindexed operational audit intervals are navigation data, not an indexed evidence chain. The UI distinguishes indexed and unindexed counts. Preview WAV and simulated input are not Evidence Bundles. Export remains disabled until the manifest/source-map integrity chain and selection export are integrated. Live partial files are excluded.
