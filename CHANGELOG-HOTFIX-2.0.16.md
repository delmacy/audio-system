# Hotfix 2.0.16 — explicit identity-plugin loading

Fixes the 2.0.15 failure:

`mxfidmux not discoverable in isolated writer environment.`

## Cause

2.0.15 isolated the writer registry and plugin path to avoid collisions between the patched MXF plugin and the stock GStreamer MXF plugin. On a fresh registry, discovery of `mxfidmux` could fail even though `gstmxfidentity.dll` had built successfully.

## Fix

- `mxf-lab write-identity` now accepts `--plugin-dll FILE`.
- It loads that exact DLL with `gst_plugin_load_file()` before creating `mxfidmux`.
- Writer `GST_PLUGIN_PATH` stays empty so the custom plugin is not auto-discovered.
- Reader still uses a separate clean registry and the stock `mxfdemux` only.
- Embedded identity report schema is bumped to v2.

## Run

Because `mxf_lab.c` changed, rebuild once:

```powershell
.\06-build-native.cmd
.\15-embedded-track-identity.cmd
```

The custom plugin itself does not need to be rebuilt if script 14 already passed.
