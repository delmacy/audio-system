Phase 8 gateway scripts.

Invoke-RecordingGatewaySipIngress.ps1 is a deterministic SIP-like ingress emulator.
It does not claim full SIP compliance. It materializes the Recording Gateway boundary:
SIP/call lifecycle + PCMA RTP passthrough -> RTSP/RTP recording session.
