# Hotfix / Gate 2.0.14 — Embedded MXF Track Identity

## Goal
Prove that semantic track identity survives inside the MXF itself and can be
recovered without consulting SQLite or a sidecar.

## Design
- Build an isolated `gstmxfidentity.dll` from the exact upstream GStreamer
  1.28.7 MXF sources.
- Do **not** replace the official `gstmxf.dll`.
- Patched factory name: `mxfidmux`.
- New request-pad properties: `track-name`, `logical-track-uuid`,
  `track-instance-uuid`.
- Serialized Track Name:
  `<DisplayName> | LT=<LogicalTrackUUID> | TI=<TrackInstanceUUID>`.
- Preserve native semantics of TrackID, TrackNumber, LinkedTrackID,
  SourceTrackID and MXF metadata InstanceUIDs.
- Write Track Name into corresponding Source Package and Material Package
  Timeline Tracks.

## Acceptance
1. Build `14-build-mxf-identity-plugin.cmd` => `mxfidmux` discoverable.
2. Rebuild `mxf-lab` with `06-build-native.cmd`.
3. Run `15-embedded-track-identity.cmd`.
4. Four audio streams exist.
5. Official `mxfdemux` returns each DisplayName + LogicalTrackUUID +
   TrackInstanceUUID from MXF structural metadata.
6. Readback requires no track sidecar/SQLite.

## Safety
The upstream GStreamer DLL is never patched in place. Remove the local plugin
folder or unset `GST_PLUGIN_PATH` to return to stock behavior.
