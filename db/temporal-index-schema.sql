PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA foreign_keys=ON;
PRAGMA busy_timeout=5000;

CREATE TABLE IF NOT EXISTS schema_version (
  version INTEGER PRIMARY KEY,
  applied_utc TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS logical_track (
  logical_track_uuid TEXT PRIMARY KEY,
  identity_version INTEGER NOT NULL,
  service_type TEXT NOT NULL,
  service_id TEXT NOT NULL,
  endpoint_id TEXT NOT NULL,
  media_flow TEXT NOT NULL DEFAULT 'mono',
  display_name TEXT NOT NULL,
  canonical_identity TEXT NOT NULL UNIQUE,
  created_utc TEXT NOT NULL,
  retired_utc TEXT
);

CREATE TABLE IF NOT EXISTS recording_file (
  file_id TEXT PRIMARY KEY,
  recorder_id TEXT NOT NULL,
  relative_path TEXT NOT NULL UNIQUE,
  state TEXT NOT NULL,
  recording_window_start_utc TEXT NOT NULL,
  recording_window_end_utc TEXT,
  segment_sequence INTEGER NOT NULL,
  topology_version INTEGER NOT NULL,
  package_creation_utc TEXT,
  first_media_utc TEXT,
  last_media_utc TEXT,
  closed_utc TEXT,
  size_bytes INTEGER,
  sha256 TEXT,
  category TEXT
);

CREATE TABLE IF NOT EXISTS track_instance (
  track_instance_uuid TEXT PRIMARY KEY,
  logical_track_uuid TEXT NOT NULL REFERENCES logical_track(logical_track_uuid),
  file_id TEXT NOT NULL REFERENCES recording_file(file_id),
  track_index INTEGER NOT NULL,
  mxf_track_id INTEGER,
  mxf_track_number INTEGER,
  track_name TEXT NOT NULL,
  valid_from_utc TEXT NOT NULL,
  valid_to_utc TEXT,
  codec TEXT NOT NULL DEFAULT 'PCMA',
  sample_rate_hz INTEGER NOT NULL DEFAULT 8000,
  channels INTEGER NOT NULL DEFAULT 1,
  track_role TEXT,
  slot_index INTEGER,
  UNIQUE(file_id, track_index)
);

CREATE TABLE IF NOT EXISTS media_interval (
  media_interval_id TEXT PRIMARY KEY,
  logical_track_uuid TEXT NOT NULL REFERENCES logical_track(logical_track_uuid),
  track_instance_uuid TEXT NOT NULL REFERENCES track_instance(track_instance_uuid),
  file_id TEXT NOT NULL REFERENCES recording_file(file_id),
  start_utc TEXT NOT NULL,
  end_utc TEXT,
  start_rtp_timestamp INTEGER,
  end_rtp_timestamp INTEGER,
  start_payload_byte_offset INTEGER,
  end_payload_byte_offset INTEGER,
  packet_count INTEGER NOT NULL DEFAULT 0,
  payload_bytes INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL DEFAULT 'OPEN'
);

CREATE TABLE IF NOT EXISTS recording_event (
  event_id TEXT PRIMARY KEY,
  event_utc TEXT NOT NULL,
  event_type TEXT NOT NULL,
  severity TEXT NOT NULL DEFAULT 'INFO',
  logical_track_uuid TEXT,
  track_instance_uuid TEXT,
  file_id TEXT,
  session_id TEXT,
  correlation_id TEXT,
  payload_json TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS ingestion_checkpoint (
  source_id TEXT PRIMARY KEY,
  source_path TEXT NOT NULL,
  byte_offset INTEGER NOT NULL DEFAULT 0,
  last_event_id TEXT,
  updated_utc TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_track_instance_lookup
  ON track_instance(logical_track_uuid, valid_from_utc, valid_to_utc);
CREATE INDEX IF NOT EXISTS ix_media_interval_lookup
  ON media_interval(logical_track_uuid, start_utc, end_utc);
CREATE INDEX IF NOT EXISTS ix_event_timeline
  ON recording_event(logical_track_uuid, event_utc);
CREATE INDEX IF NOT EXISTS ix_file_window
  ON recording_file(recording_window_start_utc, segment_sequence);


CREATE INDEX IF NOT EXISTS ix_file_category_window
  ON recording_file(category, recording_window_start_utc, segment_sequence);
CREATE INDEX IF NOT EXISTS ix_track_role
  ON track_instance(file_id, track_role, slot_index);
