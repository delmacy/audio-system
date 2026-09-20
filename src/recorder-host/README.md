# Recorder Host

## Phase 5 runtime model

`recorder-host.exe` supports two invocation modes.

### Multi-session mode

Use `--session-map <tsv>`. One process opens one RTSP listener and pre-arms every configured session before HOST_READY. Each session owns its own RTP socket, GStreamer pipeline, LT/TI identity and `StorageWriter`.

The TSV schema is:

`route_key, endpoint_id, service_id, media_flow, activity_signal, display_name, logical_uuid, instance_uuid, file_id, output_partial, output_final, lock_path, rtp_port, window_start_utc, segment_sequence, session_kind`

Fields are TAB-separated. Tabs/newlines are not allowed inside values.

### Legacy single-session mode

When `--session-map` is omitted, the Phase 3/4 flags (`--rtp-port`, `--output`, `--track-name`, `--logical-uuid`, etc.) synthesize one internal session. This preserves the earlier smoke gates.

## Storage path

Each session uses:

`appsrc -> mxfidmux -> appsink -> Win32 StorageWriter`

The Recorder owns each active file handle and route-local TEARDOWN finalizes only that writer.


## Phase 9 note

From Phase 9 onward, service media is modeled as a single mono flow by default. The TSV field formerly used for `direction` is treated as `media_flow`, normally `mono`. Legacy `--direction` remains accepted only for earlier smokes.
