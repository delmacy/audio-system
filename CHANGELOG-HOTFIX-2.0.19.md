# Hotfix 2.0.19 — deterministic reconstructed ordering

- Fixes PowerShell sorting of `OrderedDictionary` track records by using explicit key scriptblocks.
- Reconstructs file-local `track_index` deterministically from `mxf_track_id` ordering instead of parser encounter order.
- Sorts each Web Player logical row by `segment_order` oldest-to-newest.
- Adds acceptance invariants `timeline_segments_chronologically_sorted` and `track_index_reconstructed_deterministically`.
- Bumps the cross-file continuity report schema to `recorder-poc.embedded-cross-file-continuity.v2`.
- No C/plugin rebuild is required.
