# Phase 3 Acceptance

The implementation can continue without immediately running this gate. Before Phase 3 is declared target-validated, `02-one-cwp-smoke.cmd` must prove:

1. Recorder Host builds and its plugin/runtime self-test passes.
2. Recorder binds the configured RTSP and RTP addresses.
3. CWP completes ANNOUNCE -> SETUP -> RECORD -> PAUSE -> RECORD -> TEARDOWN.
4. Expected RTP packets are accepted only while the media gate is RECORDING.
5. Output is a readable single-track MXF.
6. Embedded DisplayName/LT/TI are recoverable using stock mxfdemux without the custom writer plugin.
7. `.partial` and `.lock` are absent after graceful close.
8. Required session/media/file events are present in the audit stream.
9. Final state is `CLOSED_COMPLETE`.

Crash behavior is deliberately not an acceptance item here; it belongs to the later integrated durability/recovery campaign.
