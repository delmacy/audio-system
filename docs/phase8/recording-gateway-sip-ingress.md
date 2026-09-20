# Phase 8 — Recording Gateway / SIP ingress

Status: MATERIALIZED — integrated target build/test pending.

Phase 8 introduces a Recording Gateway boundary between SIP/telephony semantics and the Recorder RTSP/RTP/MXF core.

The Recorder remains intentionally ignorant of SIP dialogs, phone call legs, re-INVITEs, REFER, ringing, answer, release and PBX-specific semantics. The Gateway maps a call/channel to an RTSP recording session and forwards PCMA RTP to the Recorder using the same contracts proven in Phases 3–7.

## Boundary

```text
SIP/PBX/emulator
      |
      |  INVITE / 180 / 200 / ACK / BYE
      |  RTP PCMA
      v
Recording Gateway
      |
      |  RTSP ANNOUNCE / SETUP / RECORD / PAUSE / TEARDOWN
      |  RTP PCMA passthrough
      v
RecorderHost
      |
      v
MXF + audit + identity
```

## Responsibilities

### Gateway owns

- SIP dialog identity.
- Call leg identity.
- Ringing / answer / release lifecycle.
- Mapping call events to recording events.
- Generating or resolving service identity for the Recorder.
- Avoiding call-leg collapse when two calls use the same endpoint/service.
- Forwarding RTP payloads without transcoding when payload is already PCMA.

### Recorder owns

- RTSP session state.
- RTP acceptance/protection.
- MXF muxing.
- File lifecycle.
- LogicalTrackUUID / TrackInstanceUUID embedding.
- Window rotation.
- Audit of recording-side state.

## Identity model for telephony

Radio may be represented by service/frequency + endpoint + direction. Telephony additionally requires a call/leg dimension, because two simultaneous calls for the same endpoint/service must not collapse into one logical recording stream.

Canonical identity extension:

```text
identity-v1|service_type=telephone|service_id=TEL-01|endpoint_id=cwp-a17|direction=rx|call_leg_id=<gateway-leg-id>
```

The Gateway should preserve SIP raw values separately from the canonical application identity:

- `sip_call_id_raw`
- `sip_from_raw`
- `sip_to_raw`
- `sip_dialog_id`
- `gateway_call_id`
- `gateway_leg_id`
- `rtsp_session_id`

## PoC scope

This phase does not implement a full SIP stack. It materializes the gateway boundary and a deterministic SIP-like emulator sufficient for later integrated acceptance:

1. Load a gateway route map.
2. Create a synthetic call leg.
3. Emit SIP-like lifecycle events.
4. Open RTSP recording session to Recorder.
5. Forward PCMA-like RTP packets.
6. Close recording session when the call is released.
7. Write gateway audit events and a correlation manifest.

## Gateway events

- `SIP_INVITE_RECEIVED`
- `SIP_RINGING`
- `SIP_ANSWERED`
- `GATEWAY_RECORDING_SESSION_OPENING`
- `GATEWAY_RECORDING_SESSION_READY`
- `GATEWAY_RTP_FORWARD_STARTED`
- `GATEWAY_RTP_FORWARD_STOPPED`
- `SIP_BYE_RECEIVED`
- `GATEWAY_RECORDING_SESSION_CLOSING`
- `GATEWAY_RECORDING_SESSION_CLOSED`
- `GATEWAY_CALL_CLOSED`

## Acceptance intent

The future integrated smoke must prove:

- One simulated SIP call creates one Recorder RTSP session.
- Gateway does not transcode PCMA payloads.
- Recorder summary reaches `CLOSED_COMPLETE`.
- Gateway and Recorder share correlation IDs.
- No SIP fields are required inside Recorder internals.
- LogicalTrackUUID is deterministic for the call leg identity.
- TrackInstanceUUID is physical-instance scoped.

## Non-goals

- Full SIP proxy behavior.
- NAT traversal.
- SRTP.
- TLS.
- real ED-137 SIP profile compliance.
- PBX integration.

Those belong to later provider/profile phases.
