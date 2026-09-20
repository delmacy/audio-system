# CHANGELOG — Phase 9 / 9.0.0

## Service Perspective MXF Matrix materialized

Phase 9 corrects the service matrix model:

- CWP clients speak RTSP/RTP directly to RecorderHost.
- Recording Gateway is only for translated ingress, such as SIP telephony or physical/legacy radio adapters.
- Voice services are one mono audio flow by default.
- No default RX/TX split.
- No artificial stereo.
- Signaling remains timeline metadata, not separate audio tracks.

### Added

- `docs/phase9/service-perspective-matrix.md`
- `docs/phase9/acceptance.md`
- `config/recorder/service-perspective-matrix.ini`
- `scenarios/service-perspective-matrix-01.ini`
- `scripts/cwp/Invoke-ServiceMonoSessionSimulator.ps1`
- `scripts/cwp/Invoke-ServicePerspectiveSimulator.ps1`
- `scripts/recorder/08-service-perspective-matrix-smoke.cmd`
- `scripts/recorder/Invoke-ServicePerspectiveMatrixSmoke.ps1`

### Identity change

Base service identity now uses:

```text
identity-v1|service_type=radio|service_id=121500|endpoint_id=cwp-a01|media_flow=mono
```

Telephone call-leg identity uses:

```text
identity-v1|service_type=telephone|service_id=tel-01|endpoint_id=gateway-sip-01|media_flow=mono|call_leg_id=leg-poc-0001
```

### Compatibility

Earlier Phase 3-8 smokes are preserved. Phase 9 introduces the corrected model going forward rather than rewriting historical gates.
