# Phase 9 — Service Perspective MXF Matrix

Phase 9 corrects the matrix model before expanding perspectives.

## Frozen rule

One recordable service is one mono media flow by default:

```text
service / frequency / call leg
  -> one RTP/UDP PCMA stream
  -> one mono audio flow
  -> one LogicalTrackUUID
  -> one MXF track
```

Do not split `RX` and `TX` by default. Do not synthesize stereo. Do not duplicate voice media to represent perspective.

`SQU`, `PTT`, `RECORD`, `PAUSE`, `RING`, `ANSWER`, `BYE`, gaps and topology changes are timeline metadata, not separate audio tracks.

## Ingestion paths

Native recording clients speak directly to the Recorder:

```text
CWP -> RTSP/RTP -> RecorderHost
```

Translated/legacy ingress goes through a boundary adapter or gateway:

```text
SIP telephony -> Recording Gateway -> RTSP/RTP -> RecorderHost
Physical/legacy radio -> Gateway/Adapter -> RTSP/RTP -> RecorderHost
```

The Gateway is not a universal hop. It exists only where translation is needed.

## Perspective model

Perspectives are indexes/views over the same logical audio, not duplicated tracks.

Examples:

```text
CWP perspective:
  CWP-A01 / RADIO 121.500
  CWP-B05 / RADIO 121.500

Service perspective:
  RADIO 121.500
  RADIO 132.700
  TEL-01 / LEG-POC-0001

Operational perspective:
  sector
  position
  service
  call leg
```

Each perspective entry points to a `LogicalTrackUUID` and time interval. The physical MXF track is resolved through `TrackInstanceUUID` and file/window metadata.

## Identity

Radio/service identity now uses `media_flow=mono` instead of `direction=rx|tx`:

```text
identity-v1|service_type=radio|service_id=121500|endpoint_id=cwp-a01|media_flow=mono
```

Telephone still includes a call leg when needed to avoid collapsing simultaneous calls:

```text
identity-v1|service_type=telephone|service_id=tel-01|endpoint_id=gateway-sip-01|media_flow=mono|call_leg_id=leg-poc-0001
```

## Non-goals

- validate target ED-137 profile details;
- remove legacy Phase 3-8 scripts;
- model target equipment that truly delivers separate physical RX/TX flows.

If a real integration later provides physically distinct flows, model them as explicit target-profile exceptions, not as the base model.
