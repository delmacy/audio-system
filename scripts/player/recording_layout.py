"""Operational recording layout and recorder capacity settings."""

from __future__ import annotations

from datetime import datetime, timedelta
import json
from pathlib import Path

from config_store import (
    connect,
    get_topology_revision,
    initialize,
    mark_topology_changed,
    utc_now,
)

ROOT = Path(__file__).resolve().parents[2]
RECORDINGS_ROOT = ROOT / "recordings"

DEFAULT_RECORDER_SETTINGS = {
    "telephone_received_slots_per_phone": "5",
    "telephone_calling_slots_per_phone": "4",
    "recording_rotation_minutes": "60",
    "topology_change_guard_seconds": "5",
}


def _ensure_settings() -> None:
    initialize()
    with connect() as con:
        for key, value in DEFAULT_RECORDER_SETTINGS.items():
            con.execute(
                "INSERT OR IGNORE INTO system_setting(key,value) VALUES(?,?)",
                (key, value),
            )


def get_recorder_settings() -> dict:
    _ensure_settings()
    with connect() as con:
        rows = {
            str(row["key"]): str(row["value"])
            for row in con.execute(
                """
                SELECT key,value FROM system_setting
                WHERE key IN (
                    'telephone_received_slots_per_phone',
                    'telephone_calling_slots_per_phone',
                    'recording_rotation_minutes',
                    'topology_change_guard_seconds'
                )
                """
            )
        }
    return {
        "telephone": {
            "received_slots_per_phone": int(rows["telephone_received_slots_per_phone"]),
            "calling_slots_per_phone": int(rows["telephone_calling_slots_per_phone"]),
            "party_identity_source": "sip_dialog",
        },
        "rotation_minutes": int(rows["recording_rotation_minutes"]),
        "topology_change_guard_seconds": int(rows["topology_change_guard_seconds"]),
        "topology_revision": get_topology_revision(),
    }


def update_recorder_settings(
    received_slots_per_phone: int,
    calling_slots_per_phone: int,
    rotation_minutes: int,
    topology_change_guard_seconds: int,
) -> dict:
    _ensure_settings()
    if not 1 <= int(received_slots_per_phone) <= 128:
        raise ValueError("Received slots per phone must be between 1 and 128")
    if not 1 <= int(calling_slots_per_phone) <= 128:
        raise ValueError("Calling slots per phone must be between 1 and 128")
    if not 1 <= int(rotation_minutes) <= 1440:
        raise ValueError("Recording rotation must be between 1 and 1440 minutes")
    if not 0 <= int(topology_change_guard_seconds) <= 300:
        raise ValueError("Topology change guard must be between 0 and 300 seconds")

    old = get_recorder_settings()
    with connect() as con:
        values = {
            "telephone_received_slots_per_phone": str(int(received_slots_per_phone)),
            "telephone_calling_slots_per_phone": str(int(calling_slots_per_phone)),
            "recording_rotation_minutes": str(int(rotation_minutes)),
            "topology_change_guard_seconds": str(int(topology_change_guard_seconds)),
        }
        for key, value in values.items():
            con.execute("UPDATE system_setting SET value=? WHERE key=?", (value, key))

    if (
        int(old["telephone"]["received_slots_per_phone"]) != int(received_slots_per_phone)
        or int(old["telephone"]["calling_slots_per_phone"]) != int(calling_slots_per_phone)
        or int(old["rotation_minutes"]) != int(rotation_minutes)
    ):
        mark_topology_changed("recorder_topology_settings_updated")
    return get_recorder_settings()


def recording_window_bounds(now: datetime | None = None) -> tuple[datetime, datetime]:
    moment = now or datetime.now().astimezone()
    if moment.tzinfo is None:
        moment = moment.astimezone()
    rotation = get_recorder_settings()["rotation_minutes"]
    minute_of_day = moment.hour * 60 + moment.minute
    start_minute_of_day = (minute_of_day // rotation) * rotation
    start = moment.replace(
        hour=(start_minute_of_day // 60) % 24,
        minute=start_minute_of_day % 60,
        second=0,
        microsecond=0,
    )
    # For unusual rotation values that can cross the day, arithmetic is safer than
    # deriving the end from clock fields.
    end = start + timedelta(minutes=rotation)
    return start, end


def seconds_until_window_end(now: datetime | None = None) -> int:
    moment = now or datetime.now().astimezone()
    if moment.tzinfo is None:
        moment = moment.astimezone()
    _, end = recording_window_bounds(moment)
    return max(1, int((end - moment).total_seconds() + 0.999))


def daily_recording_directories(now: datetime | None = None) -> dict[str, Path]:
    moment = now or datetime.now().astimezone()
    base = RECORDINGS_ROOT / f"{moment.year:04d}" / f"{moment.month:02d}" / f"{moment.day:02d}"
    result = {
        "cwp": base / "cwp",
        "radio": base / "radio",
        "telephone": base / "telephone",
    }
    for path in result.values():
        path.mkdir(parents=True, exist_ok=True)
    return result


def recording_window_paths(now: datetime | None = None) -> dict[str, dict]:
    start, end = recording_window_bounds(now)
    stamp = f"{start.year:04d}{start.month:02d}{start.day:02d}-{start.hour:02d}{start.minute:02d}"

    dirs = daily_recording_directories(start)
    result = {}
    for kind, directory in dirs.items():
        final = directory / f"{kind}-{stamp}.mxf"
        result[kind] = {
            "kind": kind,
            "directory": str(directory),
            "file": str(final),
            "file_name": final.name,
            "partial": str(final) + ".partial",
            "lock": str(final) + ".lock",
            "window_start_local": start.isoformat(timespec="seconds"),
            "window_end_local": end.isoformat(timespec="seconds"),
        }
    return result


def recording_layout_snapshot() -> dict:
    paths = recording_window_paths()
    start, end = recording_window_bounds()
    return {
        "schema": "audio-system.recording-layout.v2",
        "root": str(RECORDINGS_ROOT),
        "hierarchy": ["year", "month", "day", "category"],
        "categories": ["cwp", "radio", "telephone"],
        "paths": paths,
        "settings": get_recorder_settings(),
        "window": {
            "start_local": start.isoformat(timespec="seconds"),
            "end_local": end.isoformat(timespec="seconds"),
            "seconds_remaining": seconds_until_window_end(),
        },
        "checked_utc": utc_now(),
    }


_ensure_settings()


if __name__ == "__main__":
    print(json.dumps(recording_layout_snapshot(), ensure_ascii=False))
