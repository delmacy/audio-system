# Phase 16 — Player Interaction Modes / 16.0.0

## Added

- Web Player interaction modes: CONTINUOUS, ONLY AUDIO and ONLY ACTIVITY.
- IN/OUT selection fields in the player shell.
- Selection band on timeline.
- Activity-aware media highlighting based on overlapping signaling events.
- Explicit mode summary and effective playback window.
- Phase 16 docs, scenario and config.
- Future smoke script: `scripts/player/14-player-interaction-modes-smoke.cmd`.

## Preserved

- One service = one mono audio flow = one LogicalTrackUUID = one MXF track.
- Explicit gaps remain non-evidence media.
- No RX/TX split is introduced in the base fixture.

## Note on naming

This is a normal project evolution patch/package, not a hotfix. The term hotfix is reserved for defect repairs.
