# MXF Identity Plugin (PoC 2.0.14)

This directory builds an **isolated** GStreamer plugin from the exact upstream
GStreamer 1.28.7 MXF source. It does not overwrite the official `gstmxf.dll`.

The patched factory is `mxfidmux` and adds three request-pad properties:

- `track-name`
- `logical-track-uuid`
- `track-instance-uuid`

The resulting standards-compliant MXF Track Name is:

`<track-name> | LT=<logical-track-uuid> | TI=<track-instance-uuid>`

TrackID, TrackNumber, LinkedTrackID, SourceTrackID and the native MXF metadata
InstanceUIDs keep their original GStreamer/SMPTE semantics.

Upstream source is downloaded from the immutable GitHub tag `1.28.7` during
build and cached locally under `vendor-1.28.7/`.
