# Logical Track Identity and Topology Rollover

## Rule

Physical MXF `TrackIndex` is an address inside one file, not historical identity.
The Web Player joins recordings by `LogicalTrackUUID` and time range.

## IDs

- `LogicalTrackUUID`: deterministic UUIDv5 derived from a versioned canonical service identity.
- `TrackInstanceUUID`: UUIDv7 identifying one physical occurrence of that logical track in one MXF.
- `TrackIndex`: local position in the current file; may change at the next file/topology.
- `MXF TrackID/TrackNumber`: MXF structural identifiers; never repurposed as application IDs.
- `TrackName`: human-readable semantic name plus the LogicalTrackUUID when the custom muxer extension is enabled.

Canonical identity v1:

`identity-v1|service_type=<type>|service_id=<id>|endpoint_id=<id>|direction=<rx|tx|mix|bidir>`

Never derive LogicalTrackUUID from IP address, RTP port, SSRC, TrackIndex, file name, or mutable display text.

## SDP/RTSP provenance

Preserve the exact raw service label fields received from SDP/RTSP alongside the normalized identity:

- `SdpServiceNameRaw`
- `SdpLabelRaw`
- `SdpMidRaw`

The ED-137/profile-specific resolver will decide which fields are authoritative for a given equipment profile. The raw values remain audit evidence.

## Topology changes

Two supported policies:

- `immediate`: close/finalize current physical file part and start a new one with the new track matrix.
- `next_boundary`: keep the current matrix until the configured file boundary; the next file starts with the new matrix.

Safety override: if a newly introduced source must be recorded immediately and cannot be represented by the currently open MXF, force an immediate rollover. Configuration must never authorize media loss.

Every change emits `TOPOLOGY_CHANGE` plus specific `TRACK_ADDED`, `TRACK_REMOVED`, `TRACK_RELOCATED` and, when applicable, `FILE_ROLLOVER` events.

## Player resolution

The temporal index resolves:

`LogicalTrackUUID + requested time interval -> one or more (FileId, TrackInstanceUUID, TrackIndex, time interval)`

A logical line therefore remains continuous even if the physical track changes from `#37` to `#4` between adjacent files.

## Embedded MXF identity status

The current stock GStreamer `mxfmux` creates MXF Timeline Tracks and internally has a `track_name` field, but it does not expose a public per-request-pad setter for Track Name/UUID. Phase 2.0.13 proves the logical mapping independently and marks embedded TrackName as pending a bounded custom `mxfmux` extension.

The extension must write the same identity present in the sidecar/index into the MXF itself so an isolated file remains self-describing.
