# Hotfix 2.0.15 — isolated official MXF readback

Fixes the embedded TrackName identity gate after 2.0.14 successfully wrote the file but the readback process could not instantiate `filesrc`/`mxfdemux`.

Changes:
- writer and reader now use separate `GST_REGISTRY_1_0` files;
- writer sees the custom `gstmxfidentity.dll` through `GST_PLUGIN_PATH`;
- reader explicitly clears custom plugin paths and uses the stock/system GStreamer plugins only;
- the gate validates stock `filesrc` and `mxfdemux` before readback;
- `mxf-lab inspect-identity` reports exactly which factory is missing;
- native self-test now includes `filesrc`;
- gate 14/15 wrappers no longer pause after completion.

The intended proof is stronger: custom writer -> closed MXF -> fresh process with official mxfdemux -> TrackName/LogicalTrackUUID/TrackInstanceUUID recovered from MXF metadata.
