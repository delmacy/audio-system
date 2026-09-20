# Port Allocation Contract

Default PoC values. Profiles may override them.

- SIP: 5060/UDP (initial PoC default)
- RTSP: 8554/TCP
- RTP: 20000-29999/UDP
- RTCP: 30000-39999/UDP

Rules:
1. No component may embed these ports as immutable constants.
2. Source address/port and destination address/port must be recorded in diagnostic metadata.
3. RTP/RTCP ranges must be validated for overlap before startup.
4. External-recorder mode must print resolved bindings before any traffic is sent.
