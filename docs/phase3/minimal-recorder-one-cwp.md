# Phase 3 — Minimal Recorder + One CWP

## Purpose

Move from isolated MXF/File-Manager spikes to the first persistent Recorder process on the target Windows architecture.

The executable is `src\recorder-host\recorder-host.exe`. It accepts one RTSP recording session and one RTP/PCMA stream, writes a semantically identified MXF through the Recorder-owned Win32 storage boundary, and closes the file only after GStreamer EOS and durable flush.

## Components introduced

### Recorder Host

- TCP RTSP listener (default profile: `10.20.0.10:8554`).
- UDP RTP receiver (default first port: `10.20.0.10:20000`).
- RTSP lifecycle: OPTIONS / ANNOUNCE / SETUP / RECORD / PAUSE / GET_PARAMETER / TEARDOWN.
- RTP payload type 8 parser with sequence-gap accounting.
- GStreamer live graph using `appsrc` and custom `mxfidmux`.
- JSONL audit stream using the canonical event vocabulary.

### Win32 StorageWriter

- owns the `.mxf.partial` handle;
- allows read sharing, denies delete/write sharing;
- writes muxed MXF bytes received from `appsink`;
- maintains `.mxf.lock` state;
- flushes and promotes the file on graceful close.

### One-CWP simulator

`Invoke-OneCwpSimulator.ps1` creates real local TCP/UDP traffic on the Phase 1 addresses. It announces one radio RX service, records, pauses while the RTSP session stays alive, resumes recording, sends a keepalive, and tears down cleanly.

## Commands

Build only:

```powershell
cd scripts\recorder
.\01-build-recorder-host.cmd
```

One-CWP vertical smoke (when integration testing resumes):

```powershell
.\02-one-cwp-smoke.cmd
```

The smoke is intentionally not a prerequisite for continuing implementation work. It is the Phase 3 integration gate to run with the later full-system test campaign.

## Expected smoke evidence

- one final `.mxf`;
- no `.mxf.partial` after graceful TEARDOWN;
- no `.mxf.lock` after graceful finalization;
- one audio stream visible to ffprobe;
- `LogicalTrackUUID` and `TrackInstanceUUID` recoverable with stock `mxfdemux`;
- expected RTSP state events in JSONL;
- expected RTP packet and payload counts;
- `CLOSED_COMPLETE` only after MXF EOS + `FlushFileBuffers` + rename.

## Explicitly deferred

- multi-session recorder routing;
- RTCP processing;
- persistent radio-frequency session orchestration at scale;
- SIP/Recording Gateway;
- SQLite temporal index;
- multi-file File-Manager orchestration inside Recorder Host;
- durability watermarks and crash recovery acceptance;
- authentication/TLS/SRTP.
