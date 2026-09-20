# Observability Event Envelope v1

Required fields:

```json
{
  "schema": "recorder-poc.event.v1",
  "event_id": "uuid",
  "producer_sequence": 42,
  "utc": "2026-09-19T14:00:00.0000000Z",
  "priority": "P0",
  "event_type": "GAP_START",
  "recorder_id": "RECORDER-01",
  "service_id": "121500",
  "endpoint_id": "CWP-A17",
  "logical_track_uuid": "...",
  "session_id": "...",
  "file_id": null,
  "track_instance_uuid": null,
  "payload": {}
}
```

`producer_sequence` is monotonic inside one producer process and supports gap detection/replay diagnostics. Ordering across independent producers is not inferred from this field; UTC plus producer identity is used for merged views.
