# Embedded cross-file logical continuity gate

This gate proves that logical playback continuity can be reconstructed from two closed MXF files even when physical track order changes between files.

The writer uses the isolated `mxfidmux` extension to embed this standard TrackName payload:

`<DisplayName> | LT=<LogicalTrackUUID> | TI=<TrackInstanceUUID>`

The writer-side TSV files are deleted before readback. The reconstruction stage then uses only the two MXFs and the stock GStreamer 1.28.7 `mxfdemux` structural metadata output.

Scenario:

- Segment A: RADIO 121500 RX, RADIO 121500 TX, TEL-01 RX, RADIO 118100 RX.
- Segment B: TEL-01 RX, RADIO 132700 RX, RADIO 121500 TX, RADIO 121500 RX.
- Three logical tracks survive but move to new physical positions.
- One logical track is removed.
- One logical track is added.

Acceptance:

- 4 audio streams and 4 recovered embedded identities in each MXF.
- 3 shared LogicalTrackUUID values.
- all 3 shared tracks physically relocate.
- exactly 1 add and 1 remove event.
- no duplicate LogicalTrackUUID inside either file.
- TrackInstanceUUID is globally unique and changes across files for the same logical track.
- reconstructed player/index artifacts are built from MXF readback, not the writer TSVs, sidecars or SQLite.

Run:

`16-embedded-cross-file-continuity.cmd`
