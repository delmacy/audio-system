# Phase 4 Acceptance Contract

A persistent radio-session acceptance run uses one frequency and one CWP and requires:

- exactly one SESSION_OPEN, SETUP, SERVICE_ENABLED, TEARDOWN, SERVICE_DISABLED and SESSION_CLOSE;
- four RECORD and four PAUSE transitions in the default scenario;
- four MEDIA_START and four MEDIA_END intervals;
- the same RTSP Session ID for the whole enabled-service lifetime;
- one output MXF, not one MXF per burst;
- all active RTP payload packets recorded;
- deliberately injected PAUSED RTP packets received but excluded from recorded payload;
- keepalive requests counted and represented by one aggregated KEEPALIVE_OK audit event;
- no `.mxf.partial` or `.mxf.lock` left after graceful TEARDOWN;
- CLOSED_COMPLETE final state.

Crash, durability, recovery and endurance remain part of integrated acceptance rather than Phase 4-local blocking gates.
