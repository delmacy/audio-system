# Phase 17 Acceptance — Live Player Branch

Deferred integrated smoke: `scripts/player/15-live-player-branch-smoke.cmd`.

Acceptance expectations:

- `web/player/live.html` exists.
- Live player fixture exists and contains mono service frames.
- Base service model remains one service = one mono audio flow = one LogicalTrackUUID.
- Live UI displays selected service, buffer depth, frame count, last frame timestamp and connection state.
- Live branch contract explicitly avoids reading `.mxf.partial`.
- Live frames are marked as operational preview, not evidentiary media.
- Historical player shell remains available at `web/player/index.html`.
