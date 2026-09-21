"""Operational temporal indexer for closed shared MXF windows."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DB_PATH = ROOT / "data" / "recorder-index.sqlite"
SCHEMA_PATH = ROOT / "db" / "temporal-index-schema.sql"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def connect() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(DB_PATH, timeout=10)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys=ON")
    con.execute("PRAGMA journal_mode=WAL")
    con.execute("PRAGMA busy_timeout=5000")
    return con


def initialize() -> None:
    with connect() as con:
        con.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))
        file_columns = {row["name"] for row in con.execute("PRAGMA table_info(recording_file)")}
        if "category" not in file_columns:
            con.execute("ALTER TABLE recording_file ADD COLUMN category TEXT")
        track_columns = {row["name"] for row in con.execute("PRAGMA table_info(track_instance)")}
        if "track_role" not in track_columns:
            con.execute("ALTER TABLE track_instance ADD COLUMN track_role TEXT")
        if "slot_index" not in track_columns:
            con.execute("ALTER TABLE track_instance ADD COLUMN slot_index INTEGER")


def _hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _payload_offset(detail: str) -> int | None:
    match = re.search(r"recorded_payload_bytes=(\d+)", detail or "")
    return int(match.group(1)) if match else None


def _events(path: Path) -> list[dict]:
    if not path.is_file():
        return []
    result = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            item = json.loads(line)
            if isinstance(item, dict):
                result.append(item)
        except json.JSONDecodeError:
            continue
    return result


def _intervals(events: list[dict]) -> list[dict]:
    opened: dict[str, dict] = {}
    intervals = []
    ordinal: dict[str, int] = {}
    for event in events:
        ti = str(event.get("track_instance_uuid") or "")
        if not ti:
            continue
        kind = event.get("event")
        if kind == "MEDIA_START":
            opened[ti] = event
        elif kind == "MEDIA_END" and ti in opened:
            start = opened.pop(ti)
            n = ordinal.get(ti, 0)
            ordinal[ti] = n + 1
            intervals.append({
                "track_instance_uuid": ti,
                "logical_track_uuid": str(event.get("logical_track_uuid") or start.get("logical_track_uuid") or ""),
                "file_id": str(event.get("file_id") or start.get("file_id") or ""),
                "ordinal": n,
                "start_utc": str(start.get("ts_utc")),
                "end_utc": str(event.get("ts_utc")),
                "start_offset": _payload_offset(str(start.get("detail") or "")),
                "end_offset": _payload_offset(str(event.get("detail") or "")),
            })
    return intervals


def ingest(manifest_path: Path, audit_path: Path) -> dict:
    initialize()
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    events = _events(audit_path)
    intervals = _intervals(events)
    tracks = list(manifest.get("tracks", []))
    files = dict(manifest.get("files", {}))
    track_by_instance = {str(track["track_instance_uuid"]): track for track in tracks}

    indexed_files = 0
    indexed_tracks = 0
    indexed_intervals = 0
    now = utc_now()

    with connect() as con:
        con.execute("BEGIN IMMEDIATE")
        for category, file in files.items():
            path = Path(str(file["path"])).resolve()
            if not path.is_file():
                continue
            relative = str(path.relative_to(ROOT.resolve())).replace("\\", "/")
            file_id = str(file["file_id"])
            file_intervals = [item for item in intervals if item["file_id"] == file_id]
            first_media = min((item["start_utc"] for item in file_intervals), default=None)
            last_media = max((item["end_utc"] for item in file_intervals), default=None)
            con.execute(
                """
                INSERT INTO recording_file(
                    file_id,recorder_id,relative_path,state,recording_window_start_utc,
                    recording_window_end_utc,segment_sequence,topology_version,
                    first_media_utc,last_media_utc,closed_utc,size_bytes,sha256,category
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(file_id) DO UPDATE SET
                    relative_path=excluded.relative_path,state=excluded.state,
                    recording_window_end_utc=excluded.recording_window_end_utc,
                    first_media_utc=excluded.first_media_utc,last_media_utc=excluded.last_media_utc,
                    closed_utc=excluded.closed_utc,size_bytes=excluded.size_bytes,
                    sha256=excluded.sha256,category=excluded.category
                """,
                (
                    file_id,
                    "RECORDER-POC-01",
                    relative,
                    "CLOSED_COMPLETE",
                    str(file["recording_window_start_utc"]),
                    last_media or now,
                    int(file.get("segment_sequence", 0)),
                    2,
                    first_media,
                    last_media,
                    now,
                    path.stat().st_size,
                    _hash(path),
                    category,
                ),
            )
            indexed_files += 1

        for track in tracks:
            file_id = str(track["file_id"])
            if file_id not in {str(item["file_id"]) for item in files.values()}:
                continue
            file_row = con.execute("SELECT 1 FROM recording_file WHERE file_id=?", (file_id,)).fetchone()
            if not file_row:
                continue
            logical = str(track["logical_track_uuid"])
            instance = str(track["track_instance_uuid"])
            canonical = str(track["canonical_identity"])
            con.execute(
                """
                INSERT INTO logical_track(
                    logical_track_uuid,identity_version,service_type,service_id,endpoint_id,
                    media_flow,display_name,canonical_identity,created_utc
                ) VALUES(?,?,?,?,?,?,?,?,?)
                ON CONFLICT(logical_track_uuid) DO UPDATE SET
                    display_name=excluded.display_name,retired_utc=NULL
                """,
                (
                    logical,2,str(track["service_type"]),str(track["service_id"]),
                    str(track["endpoint_id"]),"mono",str(track["display_name"]),canonical,
                    str(files[str(track["category"])]["recording_window_start_utc"]),
                ),
            )
            own = [item for item in intervals if item["track_instance_uuid"] == instance]
            valid_from = min((item["start_utc"] for item in own), default=str(files[str(track["category"])]["recording_window_start_utc"]))
            valid_to = max((item["end_utc"] for item in own), default=now)
            con.execute(
                """
                INSERT INTO track_instance(
                    track_instance_uuid,logical_track_uuid,file_id,track_index,track_name,
                    valid_from_utc,valid_to_utc,codec,sample_rate_hz,channels,track_role,slot_index
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(track_instance_uuid) DO UPDATE SET
                    valid_to_utc=excluded.valid_to_utc,
                    track_role=excluded.track_role,slot_index=excluded.slot_index
                """,
                (
                    instance,logical,file_id,int(track["track_index"]),str(track["display_name"]),
                    valid_from,valid_to,"PCMA",8000,1,track.get("role"),track.get("slot_index"),
                ),
            )
            indexed_tracks += 1

        for item in intervals:
            if item["track_instance_uuid"] not in track_by_instance:
                continue
            media_id = str(uuid.uuid5(
                uuid.UUID("e9f0feab-fc81-4abc-a447-dd162c5f2f12"),
                f"{item['track_instance_uuid']}|{item['start_utc']}|{item['end_utc']}|{item['ordinal']}",
            ))
            con.execute(
                """
                INSERT INTO media_interval(
                    media_interval_id,logical_track_uuid,track_instance_uuid,file_id,
                    start_utc,end_utc,start_payload_byte_offset,end_payload_byte_offset,state
                ) VALUES(?,?,?,?,?,?,?,?,?)
                ON CONFLICT(media_interval_id) DO NOTHING
                """,
                (
                    media_id,item["logical_track_uuid"],item["track_instance_uuid"],item["file_id"],
                    item["start_utc"],item["end_utc"],item["start_offset"],item["end_offset"],"CLOSED",
                ),
            )
            indexed_intervals += 1

        source_id = str(uuid.uuid5(
            uuid.UUID("a5cf16eb-b05e-4e6b-876b-b904d50b6808"),
            str(audit_path.resolve()),
        ))
        last_event_id = None
        for position, event in enumerate(events):
            event_id = str(uuid.uuid5(
                uuid.UUID("0de57d0e-87df-4852-ae8d-13a5a4b45052"),
                f"{audit_path.resolve()}|{position}|{event.get('ts_utc')}|{event.get('event')}",
            ))
            last_event_id = event_id
            con.execute(
                """
                INSERT INTO recording_event(
                    event_id,event_utc,event_type,severity,logical_track_uuid,
                    track_instance_uuid,file_id,session_id,correlation_id,payload_json
                ) VALUES(?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(event_id) DO NOTHING
                """,
                (
                    event_id,str(event.get("ts_utc") or now),str(event.get("event") or "UNKNOWN"),
                    "INFO",event.get("logical_track_uuid") or None,event.get("track_instance_uuid") or None,
                    event.get("file_id") or None,event.get("session_id") or None,
                    event.get("route_key") or None,json.dumps(event,ensure_ascii=False,separators=(",", ":")),
                ),
            )

        con.execute(
            """
            INSERT INTO ingestion_checkpoint(source_id,source_path,byte_offset,last_event_id,updated_utc)
            VALUES(?,?,?,?,?)
            ON CONFLICT(source_id) DO UPDATE SET
                byte_offset=excluded.byte_offset,last_event_id=excluded.last_event_id,
                updated_utc=excluded.updated_utc
            """,
            (
                source_id,str(audit_path.resolve()),audit_path.stat().st_size if audit_path.exists() else 0,
                last_event_id,now,
            ),
        )
        con.commit()

    return {
        "database": str(DB_PATH),
        "files": indexed_files,
        "tracks": indexed_tracks,
        "media_intervals": indexed_intervals,
        "events": len(events),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    ingest_parser = sub.add_parser("ingest")
    ingest_parser.add_argument("--manifest", required=True)
    ingest_parser.add_argument("--audit", required=True)
    sub.add_parser("init")
    args = parser.parse_args()

    if args.command == "init":
        initialize()
        print(json.dumps({"database": str(DB_PATH)}))
    else:
        print(json.dumps(
            ingest(Path(args.manifest).resolve(), Path(args.audit).resolve()),
            ensure_ascii=False,
        ))


if __name__ == "__main__":
    main()
