# Phase 2 hotfix 2.0.2

- Align gst-launch MXF wiring with the official `mxfmux name=m ... ! m.` request-pad pattern.
- Normalize the Windows output path to forward slashes only for the GStreamer `filesink location` property.
- Add an explicit file-existence assertion after gst-launch; if GStreamer exits 0 without creating the expected MXF, the harness now reports the full pipeline instead of failing later in `Get-Item`.
