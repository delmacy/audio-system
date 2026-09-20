# Hotfix 2.0.18 — embedded cross-file continuity

- Added `16-embedded-cross-file-continuity.cmd`.
- Generates two MXFs with deliberately reordered/add/remove topology using embedded TrackName identity.
- Deletes writer identity TSVs before reconstruction.
- Reopens both files with isolated stock GStreamer 1.28.7 `mxfdemux`.
- Reconstructs physical-track mappings, topology events and Web Player logical rows from MXF metadata only.
- Adds duplicate LogicalTrackUUID and globally-unique TrackInstanceUUID invariants.
- No C/plugin rebuild is required after 2.0.17 is already working.
