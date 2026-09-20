# CODEX.md

This project uses `AGENTS.md` as the canonical agent/Codex handoff file.

Read `AGENTS.md` before making changes.

Critical invariants:

- CWP records directly to Recorder using RTSP/RTP. Do not route CWP through Gateway.
- Gateway is for SIP/telephony and physical/legacy radio adapters only.
- Base audio model is one mono media flow per service/call leg.
- Do not model RX/TX as default MXF tracks.
- LogicalTrackUUID is stable semantic identity; TrackInstanceUUID is physical occurrence; TrackIndex is file-local only.
- Live buffer is not evidence.
- Synthetic silence is not evidence.
- Fixture/simulation output is not evidence.
- `NOT_RUN` never becomes `PASS`.
- Use `patch` for normal evolution and reserve `hotfix` for actual defect correction.

