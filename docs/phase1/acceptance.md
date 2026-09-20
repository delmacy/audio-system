# Phase 1 Acceptance Gate

Phase 1 passes when all items below are true on the target Windows notebook.

- [ ] Microsoft KM-TEST Loopback Adapter exists.
- [ ] Adapter alias `POC-Loopback` exists and is enabled.
- [ ] `10.20.1.101` and `10.20.2.101` are configured locally.
- [ ] A UDP socket can bind explicitly to each address.
- [ ] Ten UDP datagrams travel CWP-B001 → CWP-A001 with 10/10 received.
- [ ] Ten UDP datagrams travel CWP-A001 → CWP-B001 with 10/10 received.
- [ ] `dumpcap` creates a non-empty PCAPNG during the test.
- [ ] Wireshark can display the two logical endpoint IP addresses and UDP probe ports.
- [ ] The network inventory JSON is stored with the run evidence.
- [ ] No virtualization/Hyper-V/Docker is required.

## Evidence produced

`runs/network-smoke/` should contain at least:

- `phase1-<timestamp>.pcapng`
- `phase1-<timestamp>-inventory.json`

## Non-gates

Phase 1 does not require SIP, RTSP, RTP media, Recorder, MXF, SQLite, or the Web Player. Those begin after this network gate passes.
