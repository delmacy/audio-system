# Phase 2 hotfix 2.0.13 - Logical track identity continuity

Adds the executable logical identity/topology gate.

- UUIDv5 `LogicalTrackUUID` from canonical SDP-derived service identity.
- UUIDv7 `TrackInstanceUUID` per physical file occurrence.
- TrackName contract includes semantic display name + complete logical UUID.
- Two adjacent MXFs deliberately reorder shared tracks, remove one service and add one service.
- Produces a temporal recording-track index, player logical timeline and topology event log.
- Proves player continuity is independent of physical TrackIndex.
- Adds `immediate` / `next_boundary` topology policy and required-media safety override.
- Documents bounded custom `mxfmux` extension required to embed per-track Track Name/UUID inside the MXF itself.

Run:

`13-logical-track-continuity.cmd`

Stock `mxfmux` embedded per-track naming remains a separate gate; 2.0.13 does not falsely report that capability as complete.
