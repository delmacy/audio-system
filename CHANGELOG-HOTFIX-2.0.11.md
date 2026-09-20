# Hotfix / experiment 2.0.11

- Added native `write-preencoded` mode using `appsrc -> mxfmux`.
- Removes `audiotestsrc`, `alawenc`, and per-track `queue` from the recorder-like load path.
- Adds 1000-track load matrix with 0/50/100/250/500/1000 continuously active tracks.
- Adds a 20 ms inactive-track anchor only to force track materialization during this MXF spike.
- Adds writer CPU time and peak working-set capture to the native-process helper.
- Adds JSON + CSV performance report.
- Adds ffprobe stream-count validation per matrix row.
