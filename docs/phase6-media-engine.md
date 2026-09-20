# Phase 6 — Media Engine RTP Protection

Phase 6 introduces the first dedicated RTP media-engine boundary inside `recorder-host.exe`.

The recorder no longer treats every UDP datagram that reaches the bound RTP port as safe media. Incoming packets are classified before being pushed to `appsrc`:

- malformed RTP headers are dropped and counted;
- unsupported payload types are dropped and counted;
- duplicate RTP sequence numbers are dropped and counted;
- late/out-of-order RTP packets are dropped and counted;
- forward sequence gaps are detected and counted as inferred missing packets;
- timestamp discontinuities inside an active media interval are detected and counted;
- PCMA payloads accepted in `RECORDING` state are pushed to the MXF pipeline;
- packets received while not recording remain ignored and counted, preserving the Phase 4 persistent-session semantics.

This is intentionally a minimal protection engine, not a full adaptive jitter buffer yet. It establishes the safety contract required before adding deeper recovery logic:

```text
RTP socket
  ↓
RTP parser
  ↓
Media Engine classifier
  ├─ malformed / wrong PT / duplicate / late → audit + metric + drop
  ├─ gap / timestamp discontinuity            → audit + metric + accept next usable media
  └─ valid PCMA while RECORDING                → appsrc → mxfidmux → StorageWriter
```

## New counters

The recorder summary now includes:

```text
sequence_gap_packets
duplicates
out_of_order
malformed
wrong_pt
timestamp_discontinuities
timestamp_gap_samples
```

The old Phase 3/4 fields remain present.

## New audit events

```text
RTP_DUPLICATE_DROPPED
RTP_OUT_OF_ORDER_DROPPED
RTP_MALFORMED_DROPPED
RTP_UNSUPPORTED_PAYLOAD_DROPPED
RTP_TIMESTAMP_DISCONTINUITY
GAP_START
GAP_END
```

## Future smoke

The future integrated gate is:

```powershell
scripts\recorder\05-media-engine-smoke.cmd
```

It sends a controlled RTP sequence containing good packets, a duplicate, a late/out-of-order packet, a sequence gap, timestamp discontinuities, an unsupported payload type, and a malformed RTP packet.

Expected result:

```text
PHASE 6 MEDIA ENGINE: PASS
```

The gate is materialized for the future campaign. It is not required to run while continuing construction.
