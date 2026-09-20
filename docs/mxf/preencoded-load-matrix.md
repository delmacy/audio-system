# Pre-encoded PCMA load matrix

Purpose: separate MXF/muxer cost from synthetic audio generation/encoding cost.

The legacy high-cardinality harness used one `audiotestsrc -> alawenc -> queue` branch per track. That is intentionally harsher than the Recorder, which is expected to receive G.711 A-law/PCMA already encoded over RTP.

The pre-encoded harness instead uses:

`reusable PCMA sample -> appsrc -> mxfmux`

No per-track `audiotestsrc`, `alawenc`, or `queue` is used.

## Matrix

Each run declares 1000 MXF tracks. Continuous media activity is varied through:

- 0 active
- 50 active
- 100 active
- 250 active
- 500 active
- 1000 active

Active tracks receive 5 seconds of PCMA in 100 ms chunks by default.

Inactive tracks receive a 20 ms **anchor** buffer. This anchor exists only for the spike so that the muxer is forced to materialize all 1000 tracks in the resulting MXF. It is not the intended production behavior for an idle/open recording session; production must represent no-media intervals semantically rather than writing artificial silence/media.

## Metrics

The runner records:

- writer wall time
- writer CPU time
- peak working set (RAM)
- MXF bytes
- estimated PCMA payload bytes
- MXF overhead
- effective writer MiB/s
- ffprobe audio-stream count

The output is both JSON and CSV under `runs/mxf-spike/`.

## Acceptance

A row passes when:

1. the native writer exits successfully;
2. an MXF file exists;
3. ffprobe enumerates exactly 1000 audio streams.

This test is not a playback-quality test and intentionally avoids the heavier native `inspect` path so that validation cost is not confused with writer cost.
