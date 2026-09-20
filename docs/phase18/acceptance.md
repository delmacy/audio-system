# Phase 18 Acceptance — Export Evidence Bundle

A future integrated run passes when:

- `scripts/export/16-export-evidence-bundle-smoke.cmd` completes with PASS;
- exported audio exists;
- export manifest identifies LogicalTrackUUID and mono media flow;
- source map contains FileId, TrackInstanceUUID and TrackIndex;
- gaps are explicit and are not represented as recorded audio;
- all bundle files are SHA-256 hashed;
- package hash is computed from the file-hashes manifest;
- evidence README explains limitations and source chain;
- live buffer is never accepted as evidence source.
