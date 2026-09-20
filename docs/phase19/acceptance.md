# Phase 19 Acceptance

A Phase 19 implementation is acceptable when the future smoke can produce an integrity report proving:

- SHA-256 hashes are present for MXF, recording manifest, playback plan, source map, export manifest and bundle files.
- `FileId` is consistent across recording manifest, temporal index fixture and export source map.
- `LogicalTrackUUID` is stable across all linked artifacts.
- `TrackInstanceUUID` is preserved for the physical segment used by playback/export.
- `TrackIndex` is used only as file-local track location.
- `media_flow` remains `mono`.
- Synthetic silence and gaps are labelled as non-evidence.
- Verification returns `PASS` only if every referenced file/hash is present and consistent.
