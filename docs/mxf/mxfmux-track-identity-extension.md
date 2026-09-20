# Bounded mxfmux Track Identity Extension

## Why

GStreamer `mxfmux` already constructs `MXFMetadataTimelineTrack` objects and assigns TrackID/TrackNumber. Its source also writes `track_name` for the timecode track. Stock 1.28.x does not expose a public per-audio-pad API for setting each essence track's semantic Track Name.

## Required extension

Add request-pad metadata properties (or an equivalent explicit application API) to `GstMXFMuxPad`:

- `track-name` (UTF-8 input, serialized as MXF Track Name)
- `logical-track-uuid` (application UUID string; also included in Track Name until a registered descriptive-metadata scheme is selected)
- `track-instance-uuid`

During source-package and material-package track creation:

1. copy `pad->track_name` into `track->parent.track_name` for both corresponding Timeline Tracks;
2. leave MXF `TrackID` and `TrackNumber` semantics untouched;
3. do not overload LinkedTrackID, SourceTrackID or Essence Track Number with application UUIDs;
4. preserve the same LogicalTrackUUID in sidecar/SQLite;
5. validate by closing, reopening and enumerating metadata from the MXF.

Initial interoperable Track Name format:

`<DisplayName> | LT=<LogicalTrackUUID>`

Example:

`RADIO 121500 | CWP-A17 | RX | LT=2f27...`

The complete UUID is required in the actual file; abbreviated forms are UI-only.

## Acceptance

- different files may assign different physical TrackIndex values;
- the same semantic service resolves to the same LogicalTrackUUID;
- TrackInstanceUUID differs per physical occurrence;
- reopening the MXF returns the expected Track Name for every essence track;
- sidecar/index and embedded Track Name agree;
- mismatch is `INTEGRITY_FAILURE`, not silently repaired.
