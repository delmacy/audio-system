# Phase 1 — Windows Network Foundation

## Goal

Prove that one Windows host can expose multiple logical endpoint IPv4 addresses, bind sockets to those addresses explicitly, and capture the resulting traffic independently with dumpcap/Wireshark.

This phase does **not** implement SIP, RTSP, RTP, MXF, or the Recorder yet. It creates the network substrate those components will use.

## Lab network

Default local profile:

- Adapter alias: `POC-Loopback`
- Subnet: `10.20.0.0/16`
- Lab bind IP: `10.20.0.50`
- Recorder future IP: `10.20.0.10`
- SIP switch future IP: `10.20.0.20`
- CWP-A range: `10.20.1.101` through `10.20.1.200` (up to 100)
- CWP-B range: `10.20.2.101` through `10.20.2.200` (up to 100)

The phase-1 setup script materializes only two CWP-A and two CWP-B addresses by default. This avoids adding 100 addresses before they are needed. Use `-FullProfile` later to add the full count declared in the profile.

## Why two different loopback concepts appear

`Microsoft KM-TEST Loopback Adapter` is used as a Windows network adapter on which the PoC endpoint addresses are configured.

Npcap/Wireshark may expose a separate loopback capture interface for traffic whose source and destination are local to the same Windows host. Therefore:

- **socket binding interface/address** and
- **packet capture interface**

are intentionally configured/discovered separately.

## Run order

From `scripts/network`:

1. `01-inventory.cmd`
2. `02-install-loopback.cmd` only if the KM-TEST adapter is missing
3. `03-setup-lab.cmd` from an Administrator terminal
4. `04-smoke-test.cmd`

The smoke test binds two UDP sockets to:

- CWP-A001: `10.20.1.101:41001`
- CWP-B001: `10.20.2.101:41002`

It sends ten packets B→A and ten packets A→B while dumpcap writes a PCAPNG file.

## Expected result

Console:

```text
B -> A received: 10 / 10
A -> B received: 10 / 10
UDP BIND TEST: PASS
PHASE-1 NETWORK SMOKE: PASS
```

Wireshark display filter:

```text
udp.port == 41001 || udp.port == 41002
```

The payload begins with `RECORDER-POC|PHASE1|` so the test traffic is easy to identify.

## External recorder mode

`external-recorder-template.ini` is only a template. Editing it does not change Windows networking automatically.

Run:

```powershell
.\scripts\network\Validate-NetworkProfile.ps1 -Profile .\config\profiles\external-recorder-template.ini
```

Validation is intentionally passive: it checks local configuration and does not send SIP/RTSP/RTP/ICMP traffic to the external recorder.

Actual external-recorder transmission belongs to later phases after the protocol client exists and the training/lab equipment parameters are known.

## Cleanup

To remove the PoC IPv4 aliases from `POC-Loopback`:

```powershell
.\scripts\network\Remove-PocNetwork.ps1
```

Run as Administrator.

The script does not uninstall the KM-TEST adapter.
