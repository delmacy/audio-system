"""Observed timeline data from the temporal index and closed operational MXFs.

Audit intervals are useful for navigation but are not an indexed evidence chain.
"""

from __future__ import annotations

import json
import re
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCAL_TZ = timezone(timedelta(hours=-3))
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
START_RE = re.compile(r"^(?:[01]\d|2[0-3]):[0-5]\d$")
RUN_INTERVAL_CACHE: dict[str, list[dict]] = {}


def parse_utc(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def iso(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def latest_index() -> Path | None:
    operational = ROOT / "data" / "recorder-index.sqlite"
    if operational.is_file():
        return operational
    paths = sorted((ROOT / "runs" / "index").glob("temporal-index-*/recorder-index.sqlite"), reverse=True)
    return paths[0] if paths else None


def latest_local_date() -> str:
    operational = ROOT / "runs" / "operational-recorder"
    names = [p.name for p in operational.iterdir() if p.is_dir() and re.match(r"^\d{8}-\d{9}$", p.name)] if operational.is_dir() else []
    if names:
        return max(names)[:8]
    db = latest_index()
    if db:
        with sqlite3.connect(f"file:{db.as_posix()}?mode=ro", uri=True) as con:
            row = con.execute("SELECT MAX(start_utc) FROM media_interval").fetchone()
        if row and row[0]:
            return parse_utc(row[0]).astimezone(LOCAL_TZ).strftime("%Y%m%d")
    return datetime.now(LOCAL_TZ).strftime("%Y%m%d")


def index_intervals(day: str) -> list[dict]:
    db = latest_index()
    if not db:
        return []
    day_start = datetime.strptime(day, "%Y%m%d").replace(tzinfo=LOCAL_TZ).astimezone(timezone.utc)
    day_end = day_start + timedelta(days=1)
    with sqlite3.connect(f"file:{db.as_posix()}?mode=ro", uri=True) as con:
        con.row_factory = sqlite3.Row
        rows = con.execute("""
            SELECT mi.media_interval_id, mi.start_utc, mi.end_utc, mi.logical_track_uuid,
                   mi.track_instance_uuid, lt.service_type, lt.service_id, lt.endpoint_id,
                   rf.relative_path, rf.state, ti.track_index, ti.track_role, ti.slot_index,
                   rf.category
            FROM media_interval mi
            JOIN logical_track lt ON lt.logical_track_uuid=mi.logical_track_uuid
            JOIN track_instance ti ON ti.track_instance_uuid=mi.track_instance_uuid
            JOIN recording_file rf ON rf.file_id=mi.file_id
            WHERE mi.start_utc < ? AND mi.end_utc > ? AND mi.state='CLOSED'
              AND rf.state='CLOSED_COMPLETE'
            ORDER BY mi.start_utc
        """, (iso(day_end), iso(day_start))).fetchall()
    result = []
    for row in rows:
        mxf = (ROOT / row["relative_path"]).resolve()
        allowed = (
            mxf.is_relative_to((ROOT / "recordings").resolve())
            or mxf.is_relative_to((ROOT / "runs").resolve())
        )
        if not allowed or mxf.suffix.lower() != ".mxf" or not mxf.is_file():
            continue
        result.append({"id": row["media_interval_id"], "start_utc": row["start_utc"],
                       "end_utc": row["end_utc"], "logical_track_uuid": row["logical_track_uuid"],
                       "track_instance_uuid": row["track_instance_uuid"],
                       "service_type": row["service_type"], "service_id": row["service_id"],
                       "endpoint_id": row["endpoint_id"], "mxf_name": mxf.name,
                       "track_index": int(row["track_index"]),
                       "track_role": row["track_role"], "slot_index": row["slot_index"],
                       "category": row["category"], "source": "sqlite_closed_mxf"})
    return result


def _operational_track_intervals(run: Path, track_state: dict, events: list[dict], ordinal: int) -> list[dict]:
    mxf = Path(track_state["final_mxf"]).resolve()
    allowed = (
        mxf.parent == run.resolve()
        or mxf.is_relative_to((ROOT / "recordings").resolve())
    )
    if not allowed or mxf.suffix.lower() != ".mxf" or not mxf.is_file():
        return []
    track = track_state["logical_track_uuid"]
    instance = track_state["track_instance_uuid"]
    matching = [e for e in events if e.get("logical_track_uuid") == track and e.get("track_instance_uuid") == instance]
    kinds = {e.get("event") for e in matching}
    classic_closed = {"WINDOW_CLOSED_COMPLETE", "MEDIA_COMMIT"}.issubset(kinds)
    file_id = str(track_state.get("file_id") or "")
    category = str(track_state.get("category") or "")
    shared_closed = any(
        event.get("event") == "SHARED_MXF_CLOSED_COMPLETE"
        and (
            (file_id and f"file_id={file_id}" in str(event.get("detail") or ""))
            or (category and f"category={category}" in str(event.get("detail") or ""))
        )
        for event in events
    )
    if not classic_closed and not shared_closed:
        return []
    opened = None
    items = []
    for event in matching:
        if event.get("event") == "MEDIA_START":
            opened = event.get("ts_utc")
        elif event.get("event") == "MEDIA_END" and opened:
            end = event.get("ts_utc")
            if parse_utc(end) > parse_utc(opened):
                items.append({
                    "id": f"{run.name}-{ordinal}-{len(items)}",
                    "start_utc": opened, "end_utc": end,
                    "logical_track_uuid": track, "track_instance_uuid": instance,
                    "service_type": track_state.get("service_type", "radio"),
                    "service_id": track_state["service_id"],
                    "endpoint_id": track_state["endpoint_id"],
                    "run_id": run.name,
                    "mxf_name": mxf.name,
                    "track_index": int(track_state.get("track_index", ordinal)),
                    "track_role": track_state.get("role"),
                    "slot_index": track_state.get("slot_index"),
                    "category": track_state.get("category"),
                    "source": "closed_mxf_recorder_audit_unindexed",
                })
            opened = None
    return items


def operational_intervals(day: str, run_selector: str | None = None) -> list[dict]:
    directory = ROOT / "runs" / "operational-recorder"
    if not directory.is_dir():
        return []
    runs = sorted(
        (run for run in directory.iterdir() if run.is_dir() and run.name.startswith(day + "-")),
        key=lambda run: run.name,
    )
    if run_selector == "latest":
        runs = runs[-1:] if runs else []
    elif run_selector:
        runs = [run for run in runs if run.name == run_selector]
    result = []
    for run in runs:
        state_file, audit_file = run / "operational-recorder-state.json", run / "recorder-audit.jsonl"
        if not state_file.is_file() or not audit_file.is_file():
            continue
        try:
            state = json.loads(state_file.read_text(encoding="utf-8-sig"))
            events = [json.loads(line) for line in audit_file.read_text(encoding="utf-8").splitlines() if line.strip()]
            if isinstance(state.get("tracks"), list):
                track_states = state["tracks"]
            else:
                track_states = [state]
            run_items = []
            for ordinal, track_state in enumerate(track_states):
                run_items.extend(_operational_track_intervals(run, track_state, events, ordinal))
            result.extend(run_items)
        except (OSError, ValueError, KeyError, json.JSONDecodeError):
            continue
    return result

def build_timeline(date: str | None = None, start: str | None = None, run: str | None = None) -> dict:
    if date is None:
        date = latest_local_date()
        date = f"{date[:4]}-{date[4:6]}-{date[6:]}"
    if not DATE_RE.fullmatch(date):
        raise ValueError("Data deve usar YYYY-MM-DD.")
    datetime.strptime(date, "%Y-%m-%d")
    if start is not None and not START_RE.fullmatch(start):
        raise ValueError("Início deve usar HH:MM.")
    day = date.replace("-", "")
    if run:
        intervals = operational_intervals(day, run_selector=run)
    else:
        intervals = index_intervals(day) + operational_intervals(day)
    if start is None:
        latest = max((parse_utc(s["end_utc"]).astimezone(LOCAL_TZ) for s in intervals), default=None)
        start_hour = max(0, min(22, latest.hour - 1)) if latest else 8
        start = f"{start_hour:02d}:00"
    local_start = datetime.fromisoformat(f"{date}T{start}:00").replace(tzinfo=LOCAL_TZ)
    window_start = local_start.astimezone(timezone.utc)
    window_end = window_start + timedelta(hours=2)
    active = [s for s in intervals if parse_utc(s["start_utc"]) < window_end and parse_utc(s["end_utc"]) > window_start]
    groups: dict[str, dict] = {}
    for item in active:
        endpoint = item["endpoint_id"]
        kind = "CWP" if endpoint.lower().startswith("cwp") else "TEL" if item["service_type"] == "telephone" else "RADIO"
        group_id = f"{kind}:{endpoint}"
        group = groups.setdefault(group_id, {"id": group_id, "kind": kind, "label": endpoint, "tracks": {}})
        track = group["tracks"].setdefault(item["logical_track_uuid"], {
            "id": item["logical_track_uuid"], "label": item["service_id"],
            "logicalTrackUUID": item["logical_track_uuid"], "segments": [], "sources": set(),
        })
        track["sources"].add(item["source"])
        track["segments"].append({"id": item["id"], "start_utc": item["start_utc"],
                                   "end_utc": item["end_utc"], "track_instance_uuid": item["track_instance_uuid"],
                                   "run_id": item.get("run_id"),
                                   "mxf_name": item.get("mxf_name"),
                                   "track_index": item.get("track_index"),
                                   "source": item["source"]})
    ordered = []
    for group in sorted(groups.values(), key=lambda x: (x["kind"], x["label"])):
        tracks = []
        for track in sorted(group["tracks"].values(), key=lambda x: x["label"]):
            track["sources"] = sorted(track["sources"])
            track["segments"].sort(key=lambda x: x["start_utc"])
            tracks.append(track)
        group["tracks"] = tracks
        ordered.append(group)
    return {"schema": "recorder-poc.timeline-observed.v1", "scope": "observed_closed_mxf_intervals",
            "date": date, "start_local": start, "timezone": "UTC-03:00", "run": run,
            "window_start_utc": iso(window_start), "window_end_utc": iso(window_end),
            "groups": ordered, "counts": {"groups": len(ordered),
                                       "logical_tracks": sum(len(g["tracks"]) for g in ordered),
                                       "media_intervals": len(active),
                                       "indexed_intervals": sum(s["source"] == "sqlite_closed_mxf" for s in active),
                                       "unindexed_intervals": sum(s["source"] != "sqlite_closed_mxf" for s in active)},
            "latest_available_utc": iso(max(parse_utc(s["end_utc"]) for s in intervals)) if intervals else None}
