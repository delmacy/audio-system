# CHANGELOG — Phase 8 / 8.0.0

## Recording Gateway / SIP ingress materialized

Phase 8 introduces the Recording Gateway boundary.

### Added

- `docs/phase8/recording-gateway-sip-ingress.md`
- `config/gateway/sip-ingress.ini`
- `config/recorder/sip-gateway-ingress.ini`
- `scenarios/sip-gateway-01.ini`
- `scripts/gateway/Invoke-RecordingGatewaySipIngress.ps1`
- `scripts/recorder/07-recording-gateway-smoke.cmd`
- `scripts/recorder/Invoke-RecordingGatewaySmoke.ps1`

### Contract

The Recorder stays protocol-clean. SIP/call lifecycle is represented by the Gateway, which opens a recording session through RTSP and forwards PCMA RTP to the Recorder.

```text
SIP-like call lifecycle -> Recording Gateway -> RTSP/RTP -> RecorderHost -> MXF
```

### Telephony identity

Phase 8 adds a telephone call-leg identity requirement:

```text
identity-v1|service_type=telephone|service_id=TEL-01|endpoint_id=cwp-a17|direction=rx|call_leg_id=LEG-POC-0001
```

This avoids collapsing simultaneous calls that share endpoint/service/direction.

### Future smoke

```powershell
.\07-recording-gateway-smoke.cmd
```

Expected future acceptance:

- one synthetic SIP-like call;
- one RTSP session opened by the Gateway;
- PCMA passthrough RTP;
- gateway audit correlation manifest;
- Recorder final state `CLOSED_COMPLETE`;
- no SIP semantics inside RecorderHost internals.

### Non-goals

- full SIP compliance;
- PBX integration;
- TLS/SRTP;
- NAT traversal;
- ED-137 profile validation.

Those remain later provider/profile work.
