PHASE 2 - MXF SPIKE

Run in this order:

00-inventory.cmd
01-single-track.cmd
02-two-track.cmd
03-scale-2-10-50-100.cmd
04-track-identity.cmd

Optional inspection:
05-inspect.cmd <file.mxf>

For the real high-cardinality gate:
06-build-native.cmd
07-native-scale-100-500-1000.cmd
08-crash-probe.cmd

Do not treat 500/1000 support as proven until the native scale command has run successfully on the target Windows machine.

Recorder-like pre-encoded load test:
09-preencoded-load-matrix.cmd

This keeps 1000 tracks materialized while varying continuous active media. It uses appsrc + pre-encoded PCMA (no per-track alawenc/audiotestsrc).

Logical identity/topology continuity gate:
13-logical-track-continuity.cmd

This creates two adjacent MXFs whose physical track order changes and proves the player/index can join the same semantic streams by LogicalTrackUUID. Embedded per-track TrackName in stock mxfmux is still pending the custom muxer extension.

Embedded cross-file continuity gate:
16-embedded-cross-file-continuity.cmd

Requires the 2.0.17 embedded identity gate to be working. No rebuild is required. This test reconstructs identity and player continuity from the two MXFs after deleting the writer TSV inputs.

File Manager pre-arm capacity gate:
17-file-manager-prearm-capacity.cmd

This proves 100/100 next-window file handles are created, locked and ARMED before T0. The boundary path performs activation only. The probe does not produce valid MXF essence.
