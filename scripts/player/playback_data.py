"""Real playback boundary for closed operational Recorder MXFs.

This module resolves a LogicalTrackUUID against operational recorder state/audit,
decodes the actual MXF audio with FFmpeg, and builds a synchronized PCM WAV over
an explicit UTC window. Gaps are presentation silence, never evidence audio.
"""

from __future__ import annotations

import hashlib
import json
import shutil
import struct
import subprocess
import uuid
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNS = (ROOT / "runs" / "operational-recorder").resolve()
CACHE = ROOT / "runs" / "playback" / "http-cache"
SAMPLE_RATE = 8000
BYTES_PER_SAMPLE = 2
BYTES_PER_MS = SAMPLE_RATE * BYTES_PER_SAMPLE / 1000.0
MAX_WINDOW_SECONDS = 15 * 60


def parse_utc(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def iso(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def _read_audit(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def _track_states(state: dict) -> list[dict]:
    tracks = state.get("tracks")
    return tracks if isinstance(tracks, list) else [state]


def _validate_uuid(value: str) -> str:
    return str(uuid.UUID(value))


def _candidate_tracks(logical_track_uuid: str) -> list[tuple[Path, dict, list[dict]]]:
    logical_track_uuid = _validate_uuid(logical_track_uuid)
    candidates: list[tuple[Path, dict, list[dict]]] = []
    if not RUNS.is_dir():
        return candidates

    for run in sorted((p for p in RUNS.iterdir() if p.is_dir()), reverse=True):
        state_path = run / "operational-recorder-state.json"
        audit_path = run / "recorder-audit.jsonl"
        if not state_path.is_file() or not audit_path.is_file():
            continue
        try:
            state = _read_json(state_path)
            events = _read_audit(audit_path)
            for track in _track_states(state):
                if str(track.get("logical_track_uuid", "")).lower() == logical_track_uuid.lower():
                    candidates.append((run, track, events))
        except (OSError, ValueError, KeyError, json.JSONDecodeError):
            continue
    return candidates


def resolve_operational_track(logical_track_uuid: str) -> dict:
    for run, track, events in _candidate_tracks(logical_track_uuid):
        mxf = Path(track["final_mxf"]).resolve()
        if mxf.parent != run.resolve() or mxf.suffix.lower() != ".mxf" or not mxf.is_file():
            continue

        instance = str(track["track_instance_uuid"])
        lt = str(track["logical_track_uuid"])
        matching = [
            event for event in events
            if str(event.get("logical_track_uuid", "")) == lt
            and str(event.get("track_instance_uuid", "")) == instance
        ]
        kinds = {event.get("event") for event in matching}
        if not {"WINDOW_CLOSED_COMPLETE", "MEDIA_COMMIT"}.issubset(kinds):
            continue

        intervals = []
        opened = None
        for event in matching:
            if event.get("event") == "MEDIA_START":
                opened = event.get("ts_utc")
            elif event.get("event") == "MEDIA_END" and opened:
                end = event.get("ts_utc")
                if end and parse_utc(end) > parse_utc(opened):
                    intervals.append({"start_utc": opened, "end_utc": end})
                opened = None

        if intervals:
            return {
                "run": run,
                "mxf": mxf,
                "track": track,
                "intervals": intervals,
            }

    raise LookupError(f"No closed operational MXF found for LogicalTrackUUID {logical_track_uuid}")


def build_operational_plan(logical_track_uuid: str, from_utc: str | None = None, to_utc: str | None = None) -> dict:
    resolved = resolve_operational_track(logical_track_uuid)
    intervals = resolved["intervals"]
    natural_from = parse_utc(intervals[0]["start_utc"])
    natural_to = parse_utc(intervals[-1]["end_utc"])
    start = parse_utc(from_utc) if from_utc else natural_from
    end = parse_utc(to_utc) if to_utc else natural_to
    if end <= start:
        raise ValueError("to must be greater than from")
    if (end - start).total_seconds() > MAX_WINDOW_SECONDS:
        raise ValueError(f"playback window exceeds {MAX_WINDOW_SECONDS} seconds")

    items = []
    cursor = start
    for interval in intervals:
        a = parse_utc(interval["start_utc"])
        z = parse_utc(interval["end_utc"])
        if z <= start or a >= end:
            continue
        clipped_a = max(a, start)
        clipped_z = min(z, end)
        if clipped_a > cursor:
            items.append({
                "kind": "gap",
                "reason": "no_recorded_media",
                "from_utc": iso(cursor),
                "to_utc": iso(clipped_a),
                "duration_ms": round((clipped_a - cursor).total_seconds() * 1000, 3),
            })
        items.append({
            "kind": "media",
            "valid_from_utc": iso(clipped_a),
            "valid_to_utc": iso(clipped_z),
            "duration_ms": round((clipped_z - clipped_a).total_seconds() * 1000, 3),
        })
        cursor = max(cursor, clipped_z)

    if cursor < end:
        items.append({
            "kind": "gap",
            "reason": "no_recorded_media",
            "from_utc": iso(cursor),
            "to_utc": iso(end),
            "duration_ms": round((end - cursor).total_seconds() * 1000, 3),
        })

    track = resolved["track"]
    return {
        "schema": "audio-system.operational-playback-plan.v1",
        "source_scope": "closed_operational_mxf_recorder_audit",
        "logical_track_uuid": str(track["logical_track_uuid"]),
        "track_instance_uuid": str(track["track_instance_uuid"]),
        "service_id": str(track.get("service_id", "")),
        "endpoint_id": str(track.get("endpoint_id", "")),
        "service_type": str(track.get("service_type", "radio")),
        "from_utc": iso(start),
        "to_utc": iso(end),
        "fabricate_recorded_silence": False,
        "presentation_gap_silence": True,
        "items": items,
        "summary": {
            "media_items": sum(item["kind"] == "media" for item in items),
            "gap_items": sum(item["kind"] == "gap" for item in items),
            "media_ms": round(sum(item["duration_ms"] for item in items if item["kind"] == "media"), 3),
            "gap_ms": round(sum(item["duration_ms"] for item in items if item["kind"] == "gap"), 3),
        },
    }


def _ffmpeg() -> str:
    command = shutil.which("ffmpeg")
    if not command:
        raise RuntimeError("FFmpeg was not found in PATH")
    return command


def _decode_pcm(mxf: Path) -> bytes:
    proc = subprocess.run(
        [_ffmpeg(), "-hide_banner", "-loglevel", "error", "-i", str(mxf),
         "-map", "0:a:0", "-ac", "1", "-ar", str(SAMPLE_RATE), "-c:a", "pcm_s16le", "-f", "s16le", "-"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=60,
    )
    if proc.returncode != 0:
        detail = proc.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"FFmpeg decode failed: {detail}")
    if not proc.stdout:
        raise RuntimeError("FFmpeg decoded no audio")
    return proc.stdout


def _wav_bytes(pcm: bytes) -> bytes:
    data_size = len(pcm)
    header = (
        b"RIFF" + struct.pack("<I", 36 + data_size) + b"WAVE"
        + b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, SAMPLE_RATE, SAMPLE_RATE * 2, 2, 16)
        + b"data" + struct.pack("<I", data_size)
    )
    return header + pcm


def render_operational_wav(logical_track_uuid: str, from_utc: str | None = None, to_utc: str | None = None) -> tuple[dict, bytes]:
    resolved = resolve_operational_track(logical_track_uuid)
    plan = build_operational_plan(logical_track_uuid, from_utc, to_utc)
    start = parse_utc(plan["from_utc"])
    end = parse_utc(plan["to_utc"])
    total_ms = (end - start).total_seconds() * 1000
    total_bytes = int(round(total_ms * BYTES_PER_MS))
    if total_bytes % 2:
        total_bytes += 1

    cache_key = hashlib.sha256(
        (str(resolved["mxf"]) + "|" + plan["from_utc"] + "|" + plan["to_utc"]
         + "|" + str(resolved["mxf"].stat().st_mtime_ns)).encode("utf-8")
    ).hexdigest()
    CACHE.mkdir(parents=True, exist_ok=True)
    cache_path = CACHE / f"{cache_key}.wav"
    if cache_path.is_file():
        return plan, cache_path.read_bytes()

    decoded = _decode_pcm(resolved["mxf"])
    output = bytearray(total_bytes)
    source_cursor = 0

    for interval in resolved["intervals"]:
        a = parse_utc(interval["start_utc"])
        z = parse_utc(interval["end_utc"])
        natural_ms = max(0.0, (z - a).total_seconds() * 1000)
        natural_bytes = int(round(natural_ms * BYTES_PER_MS))
        natural_bytes -= natural_bytes % 2
        source_chunk = decoded[source_cursor:source_cursor + natural_bytes]
        source_cursor += natural_bytes

        if z <= start or a >= end or not source_chunk:
            continue

        clipped_a = max(a, start)
        clipped_z = min(z, end)
        clip_from_ms = max(0.0, (clipped_a - a).total_seconds() * 1000)
        clip_duration_ms = max(0.0, (clipped_z - clipped_a).total_seconds() * 1000)
        chunk_from = int(round(clip_from_ms * BYTES_PER_MS))
        chunk_from -= chunk_from % 2
        chunk_len = int(round(clip_duration_ms * BYTES_PER_MS))
        chunk_len -= chunk_len % 2
        chunk = source_chunk[chunk_from:chunk_from + chunk_len]

        target_ms = max(0.0, (clipped_a - start).total_seconds() * 1000)
        target = int(round(target_ms * BYTES_PER_MS))
        target -= target % 2
        writable = min(len(chunk), len(output) - target)
        if writable > 0:
            output[target:target + writable] = chunk[:writable]

    wav = _wav_bytes(bytes(output))
    cache_path.write_bytes(wav)
    return plan, wav
