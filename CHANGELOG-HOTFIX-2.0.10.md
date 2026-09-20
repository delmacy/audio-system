# Hotfix 2.0.10

- Structural MXF inspection now exits on `mxfdemux::no-more-pads` instead of waiting for full media EOS.
- Added `--expected-tracks N` to `mxf-lab inspect`.
- Structural inspection succeeds only when `no-more-pads` is received and the discovered track count matches the expected count.
- Teardown now occurs after dynamic-pad construction completes, reducing GLib `finalized while still in-construction` diagnostics caused by timeout/forced teardown.
- The scale runner passes the expected track count to the native inspector.
- Full media/EOS validation remains a separate concern from structural enumeration.
