# CHANGELOG — Phase 22 / 22.0.0

## Added

- Integrated Acceptance Plan documentation.
- Integrated campaign configuration.
- Integrated acceptance scenario spanning Phase 1 through Phase 21.
- Deterministic PowerShell harness for aggregation smoke.
- Final report contract for JSON, Markdown and CSV outputs.

## Preserved

- CWP direct RTSP/RTP path to Recorder.
- Gateway limited to translated ingress.
- Mono service media model.
- LogicalTrackUUID and TrackInstanceUUID identity split.
- Live branch not treated as evidential audio.
- Synthetic silence not treated as recorded evidence.

## Notes

This phase materializes acceptance orchestration. The deterministic smoke validates report aggregation and gating semantics; it does not replace real native Windows execution of each gate.
