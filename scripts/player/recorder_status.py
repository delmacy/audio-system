"""Observed recorder status for the local Audio System runtime."""

from __future__ import annotations

import configparser
import json
import socket
from datetime import datetime, timezone
from pathlib import Path

from config_store import list_services
from recording_layout import recording_layout_snapshot

ROOT = Path(__file__).resolve().parents[2]
PROFILE = ROOT / "config" / "profiles" / "local-poc.ini"
RUNS_ROOT = ROOT / "runs" / "operational-recorder"


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _profile() -> tuple[str | None, int | None]:
    if not PROFILE.is_file():
        return None, None
    parser = configparser.ConfigParser()
    parser.read(PROFILE, encoding="utf-8")
    if not parser.has_section("recorder"):
        return None, None
    ip = parser.get("recorder", "ip", fallback="").strip() or None
    port = parser.getint("recorder", "rtsp_port", fallback=0) or None
    return ip, port


def _rtsp_reachable(ip: str | None, port: int | None) -> bool:
    if not ip or not port:
        return False
    try:
        with socket.create_connection((ip, port), timeout=0.20):
            return True
    except OSError:
        return False


def _current_run() -> Path | None:
    pointer = RUNS_ROOT / "current-run.txt"
    if pointer.is_file():
        try:
            raw = pointer.read_text(encoding="utf-8-sig").strip()
            if raw:
                candidate = Path(raw)
                if not candidate.is_absolute():
                    candidate = (ROOT / candidate).resolve()
                else:
                    candidate = candidate.resolve()
                if candidate.is_relative_to(RUNS_ROOT.resolve()) and candidate.is_dir():
                    return candidate
        except OSError:
            pass

    if not RUNS_ROOT.is_dir():
        return None
    runs = sorted((path for path in RUNS_ROOT.iterdir() if path.is_dir()), key=lambda path: path.name)
    return runs[-1] if runs else None


def _state(run: Path | None) -> dict | None:
    if not run:
        return None
    state_file = run / "operational-recorder-state.json"
    if not state_file.is_file():
        return None
    try:
        payload = json.loads(state_file.read_text(encoding="utf-8-sig"))
        return payload if isinstance(payload, dict) else None
    except (OSError, json.JSONDecodeError):
        return None


def _mxf_from_state(state: dict | None) -> Path | None:
    if not state:
        return None
    value = state.get("final_mxf")
    if not value:
        tracks = state.get("tracks")
        if isinstance(tracks, list):
            for track in tracks:
                if isinstance(track, dict) and track.get("final_mxf"):
                    value = track["final_mxf"]
                    break
    if not value:
        return None
    try:
        return Path(str(value)).resolve()
    except OSError:
        return None


def _category_file_status(layout: dict, state: dict | None = None) -> dict:
    result = {}
    selected_files = state.get("files", {}) if state and isinstance(state.get("files"), dict) else {}
    for kind, item in layout["paths"].items():
        selected = selected_files.get(kind)
        if isinstance(selected, dict) and selected.get("path"):
            item = {
                **item,
                "file": str(selected["path"]),
                "file_name": Path(str(selected["path"])).name,
                "partial": str(selected.get("partial") or (str(selected["path"]) + ".partial")),
                "lock": str(selected.get("lock") or (str(selected["path"]) + ".lock")),
            }
        path = Path(str(item["file"]))
        directory = Path(str(item["directory"]))
        latest = None
        if directory.is_dir():
            candidates = sorted(directory.glob("*.mxf"), key=lambda p: p.stat().st_mtime, reverse=True)
            latest = candidates[0] if candidates else None
        selected_exists = path.is_file()
        result[kind] = {
            **item,
            "exists": selected_exists,
            "size_bytes": path.stat().st_size if selected_exists else None,
            "latest_file": latest.name if latest else None,
            "latest_file_path": str(latest) if latest else None,
            "latest_size_bytes": latest.stat().st_size if latest else None,
        }
    return result


def build_recorder_status() -> dict:
    ip, port = _profile()
    reachable = _rtsp_reachable(ip, port)
    run = _current_run()
    state = _state(run)
    mxf = _mxf_from_state(state)

    tracks = state.get("tracks") if state else None
    track_count = int(state.get("track_count", len(tracks) if isinstance(tracks, list) else 0)) if state else 0
    recorder_state = str(state.get("status", "UNKNOWN")) if state else "NO_RUN"

    active_markers = {"RECORDING", "ACTIVE", "OPEN", "RUNNING", "READY", "READY_IDLE"}
    recording = recorder_state.upper() in active_markers
    if mxf and mxf.with_suffix(mxf.suffix + ".partial").exists():
        recording = True

    runtime_status = "recording" if reachable and recording else "online" if reachable else "offline"
    if not ip or not port:
        runtime_status = "unconfigured"

    layout = recording_layout_snapshot()
    category_files = _category_file_status(layout, state)
    services = list_services()
    telephone_count = sum(1 for service in services if service.get("kind") == "TEL")
    received_slots = int(layout["settings"]["telephone"]["received_slots_per_phone"])
    calling_slots = int(layout["settings"]["telephone"]["calling_slots_per_phone"])
    telephone_track_capacity = telephone_count * (received_slots + calling_slots)

    file_exists = bool(mxf and mxf.is_file())
    file_size = mxf.stat().st_size if file_exists and mxf else None

    selected_file = None
    selected_file_path = None
    if mxf:
        selected_file = mxf.name
        try:
            selected_file_path = str(mxf.relative_to(ROOT))
        except ValueError:
            selected_file_path = str(mxf)

    return {
        "schema": "audio-system.recorder-status.v1",
        "checked_utc": _utc_now(),
        "runtime_status": runtime_status,
        "rtsp_reachable": reachable,
        "recorder": {
            "ip": ip,
            "rtsp_port": port,
            "rtsp_base_url": f"rtsp://{ip}:{port}" if ip and port else None,
        },
        "recording": {
            "state": recorder_state,
            "is_recording": recording,
            "run_id": run.name if run else None,
            "selected_file": selected_file,
            "selected_file_path": selected_file_path,
            "file_exists": file_exists,
            "file_size_bytes": file_size,
            "shared_mxf": bool(state.get("shared_mxf", False)) if state else False,
            "track_count": track_count,
            "file_id": state.get("file_id") if state else None,
            "generated_utc": state.get("generated_utc") if state else None,
        },
        "recording_layout": {
            **layout,
            "files": category_files,
        },
        "telephone_capacity": {
            "registered_phones": telephone_count,
            "received_slots_per_phone": received_slots,
            "calling_slots_per_phone": calling_slots,
            "party_identity_source": "sip_dialog",
            "tracks_per_phone": received_slots + calling_slots,
            "total_track_capacity": telephone_track_capacity,
        },
        "metrics": {
            "disk": None,
            "cpu": None,
            "memory": None,
            "network": None,
        },
    }
