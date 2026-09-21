"""Operational recording layout and recorder capacity settings."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

from config_store import connect, initialize, utc_now

ROOT = Path(__file__).resolve().parents[2]
RECORDINGS_ROOT = ROOT / "recordings"

DEFAULT_RECORDER_SETTINGS = {
    "telephone_ringing_slots_per_phone": "5",
    "telephone_calling_slots_per_phone": "4",
    "recording_rotation_minutes": "60",
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
                    'telephone_ringing_slots_per_phone',
                    'telephone_calling_slots_per_phone',
                    'recording_rotation_minutes'
                )
                """
            )
        }
    return {
        "telephone": {
            "ringing_slots_per_phone": int(rows["telephone_ringing_slots_per_phone"]),
            "calling_slots_per_phone": int(rows["telephone_calling_slots_per_phone"]),
        },
        "rotation_minutes": int(rows["recording_rotation_minutes"]),
    }


def update_recorder_settings(
    ringing_slots_per_phone: int,
    calling_slots_per_phone: int,
    rotation_minutes: int,
) -> dict:
    _ensure_settings()
    if not 1 <= int(ringing_slots_per_phone) <= 128:
        raise ValueError("Ringing slots per phone must be between 1 and 128")
    if not 1 <= int(calling_slots_per_phone) <= 128:
        raise ValueError("Calling slots per phone must be between 1 and 128")
    if not 1 <= int(rotation_minutes) <= 1440:
        raise ValueError("Recording rotation must be between 1 and 1440 minutes")

    with connect() as con:
        values = {
            "telephone_ringing_slots_per_phone": str(int(ringing_slots_per_phone)),
            "telephone_calling_slots_per_phone": str(int(calling_slots_per_phone)),
            "recording_rotation_minutes": str(int(rotation_minutes)),
        }
        for key, value in values.items():
            con.execute("UPDATE system_setting SET value=? WHERE key=?", (value, key))
    return get_recorder_settings()


def daily_recording_directories(now: datetime | None = None) -> dict[str, Path]:
    moment = now or datetime.now()
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
    moment = now or datetime.now()
    settings = get_recorder_settings()
    rotation = settings["rotation_minutes"]

    minute_of_day = moment.hour * 60 + moment.minute
    window_start_minute = (minute_of_day // rotation) * rotation
    start_hour = (window_start_minute // 60) % 24
    start_minute = window_start_minute % 60
    stamp = f"{moment.year:04d}{moment.month:02d}{moment.day:02d}-{start_hour:02d}{start_minute:02d}"

    dirs = daily_recording_directories(moment)
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
        }
    return result


def recording_layout_snapshot() -> dict:
    paths = recording_window_paths()
    return {
        "schema": "audio-system.recording-layout.v1",
        "root": str(RECORDINGS_ROOT),
        "hierarchy": ["year", "month", "day", "category"],
        "categories": ["cwp", "radio", "telephone"],
        "paths": paths,
        "settings": get_recorder_settings(),
        "checked_utc": utc_now(),
    }


_ensure_settings()
