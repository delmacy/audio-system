# Phase 11 Acceptance

Future integrated gate must prove:
1. schema initializes in WAL mode;
2. two physical MXFs with the same LogicalTrackUUID and different TrackInstanceUUIDs are indexed;
3. query across the boundary returns both segments in temporal order;
4. explicit gap remains a gap;
5. event overlay query returns SQU/PTT/RING/ANSWER/RELEASE/GAP/TOPOLOGY events;
6. duplicate event ingestion is idempotent;
7. checkpoint restart does not duplicate rows;
8. Recorder continues when indexer is stopped.
