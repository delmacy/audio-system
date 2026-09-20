# CHANGELOG — Phase 15 / 15.0.0

## Added

- Web Player static shell.
- Service tree fixture for mono service model.
- Historical interval controls.
- Timeline with media blocks, explicit gaps and signaling events.
- Segment table and export bundle panel.
- Smoke harness for static UI contract validation.

## Preserved

- One service = one mono media flow = one LogicalTrackUUID.
- No base RX/TX split.
- Player consumes playback plan; it does not resolve physical MXF topology by itself.

## Status

`MATERIALIZED`. Requires future integrated smoke to become validated.
