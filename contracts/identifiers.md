# Canonical Identifiers

All components must preserve these identifiers end-to-end.

## EndpointId
Logical equipment endpoint.
Examples:
- `CWP-A017`
- `CWP-B004`
- `TEL-03`
- `RADIO-A`

## ServiceId
Logical service being recorded.
Examples:
- `TEL-03`
- `RADIO-A`

## GlobalSessionId
Recorder-PoC generated correlation identifier spanning signaling, recording and storage.
Format:
`GS-YYYYMMDDTHHMMSSmmm-XXXXXXXX`

## RecordingSessionId
Logical recording session identifier.
Format:
`RS-YYYYMMDDTHHMMSSmmm-XXXXXXXX`

## SIP Call-ID
Preserve the exact SIP Call-ID received/generated. Never replace it with IP/port identity.

## RTSP Session-ID
Preserve the exact RTSP Session identifier negotiated for the recording session.

## RTP SSRC
Store unsigned 32-bit SSRC per RTP source. SSRC alone is not a globally unique session identity.

## TrackUID
Stable unique ID for one physical/logical recording track.
Format:
`TRK-<UUID>`

## FileId
Stable ID for one physical recording file or fragment.
Format:
`FILE-<UUID>`

## TopologyVersion
Monotonic integer scoped to a Recorder run.
Starts at `1`. Increment whenever endpoint/service membership relevant to recording changes.

## RunId
Acceptance/simulation run identifier.
Format:
`RUN-YYYYMMDD-HHMMSS-XXX`

## LogicalTrackUUID
Historical semantic identity used by the player/index to join the same logical service across files and topology versions.

Generation: UUIDv5 under the immutable Recorder logical-track namespace from a versioned canonical identity:
`identity-v1|service_type=...|service_id=...|endpoint_id=...|direction=...`

Properties:
- deterministic for the same semantic identity;
- independent of TrackIndex, MXF TrackID/TrackNumber, RTP port, SSRC and file name;
- must be copied to the recording index/manifest and, after the custom muxer extension, into MXF Track Name/descriptive metadata.

## TrackInstanceUUID
UUIDv7 identifying one physical occurrence of a logical track in one recording file/fragment.
Changes whenever a new physical track instance is created, even when LogicalTrackUUID remains the same.

## TrackIndex
Local zero/one-based application position (the implementation must state which convention is used). It is not historical identity and may change between files.
