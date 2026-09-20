# Phase 2 — MXF spike

## Decision under test

Use GStreamer `mxfmux`/`mxfdemux` as the first implementation candidate for MXF storage of G.711 A-law (PCMA) tracks.

The critical property is that `mxfmux` exposes request pads named `alaw_audio_sink_%u` accepting `audio/x-alaw`. This lets the spike create one logical MXF audio track per recording leg without transcoding PCMA to another codec.

## Test ladder

1. Prerequisite inventory.
2. One A-law track, 8 kHz mono.
3. Two independent tracks.
4. Track identity test: numeric TrackIndex + stable TrackUID + human DisplayName sidecar, plus in-band metadata capability inspection.
5. `gst-launch` matrix: 2 / 10 / 50 / 100 tracks.
6. Build the native `mxf-lab` harness.
7. Native matrix: 100 / 500 / 1000 tracks.
8. Re-open/demux every output and count exposed tracks.
9. Intentional writer termination without EOS/footer and reopen attempt.

## Why two harnesses?

`gst-launch-1.0` is ideal for proving codec/caps/muxer compatibility with almost no custom code, but very large generated command lines are a poor way to represent 500–1000 independent tracks on Windows. The native harness creates the same GStreamer graph programmatically and removes the command-line-size variable from the scale test.

## Acceptance

A candidate profile is accepted only if:

- one and two track files mux and demux as A-law at 8 kHz;
- track independence is preserved;
- every logical track has a numeric TrackIndex, stable TrackUID and human-readable DisplayName in the semantic track map;
- any in-band MXF naming support is measured, but the PoC never relies on a human-readable name as the identity key;
- at least 100 tracks work through the CLI harness;
- the native harness can create and reopen 500 and 1000 tracks, or gives a reproducible limit that drives a revised storage segmentation strategy;
- file size grows approximately with active payload rather than reserved/empty capacity;
- normal close yields a readable MXF;
- crash behavior is measured and documented rather than assumed.

The crash probe does **not** require an interrupted MXF to be readable as-is. If it is not, that result becomes an explicit recovery requirement (partitioning, checkpoint strategy, fragments, or sidecar journal) for the Recorder.

## Non-goals

This phase does not implement RTSP, RTP ingest, SQLite, the Web Player, dual-perspective routing, or the final evidence model. It only validates the storage primitive before the Recorder depends on it.
