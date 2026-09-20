# Phase 17 — Live Player Branch / 17.0.0

## Added

- Live Player branch contract separate from historical playback.
- `web/player/live.html` operational live preview shell.
- Live fixture containing mono service frames and live events.
- Live branch config with latency/buffer targets.
- Future smoke script: `scripts/player/15-live-player-branch-smoke.cmd`.

## Preserved

- Live preview does not read `.mxf.partial`.
- Live buffer is not evidence audio.
- Historical playback/export remains the evidentiary path.
- One service = one mono audio flow = one LogicalTrackUUID = one MXF track.

## Naming

This is a normal project evolution patch/package, not a hotfix.
