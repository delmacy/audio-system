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
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNS = (ROOT / "runs" / "operational-recorder").resolve()
CACHE = ROOT / "runs" / "playback" / "http-cache"
SAMPLE_RATE = 8000
BYTES_PER_SAMPLE = 2
BYTES_PER_MS = SAMPLE_RATE * BYTES_PER_SAMPLE / 1000.0
MAX_WINDOW_SECONDS = 15 * 60
EDIT_UNIT_NS = 100_000_000
SAMPLES_PER_EDIT_UNIT = SAMPLE_RATE // 10
GC_ESSENCE_PREFIX = bytes.fromhex("060e2b34010201010d010301")


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


def _matching_events(track: dict, events: list[dict]) -> list[dict]:
    instance = str(track["track_instance_uuid"])
    logical = str(track["logical_track_uuid"])
    return [
        event for event in events
        if str(event.get("logical_track_uuid", "")) == logical
        and str(event.get("track_instance_uuid", "")) == instance
    ]


def _media_intervals(matching: list[dict], confirmed_end: datetime | None = None) -> list[dict]:
    intervals: list[dict] = []
    opened: str | None = None
    for event in matching:
        if event.get("event") == "MEDIA_START":
            opened = event.get("ts_utc")
        elif event.get("event") == "MEDIA_END" and opened:
            end = event.get("ts_utc")
            if end:
                a, z = parse_utc(opened), parse_utc(end)
                if confirmed_end is not None:
                    z = min(z, confirmed_end)
                if z > a:
                    intervals.append({"start_utc": iso(a), "end_utc": iso(z)})
            opened = None
    if opened and confirmed_end is not None:
        a = parse_utc(opened)
        if confirmed_end > a:
            intervals.append({"start_utc": iso(a), "end_utc": iso(confirmed_end), "current": True})
    return intervals


def _range_overlaps(start: datetime, end: datetime, from_utc: str | None, to_utc: str | None) -> bool:
    requested_start = parse_utc(from_utc) if from_utc else start
    requested_end = parse_utc(to_utc) if to_utc else end
    return requested_start < end and requested_end > start


def _load_growing_candidate(run: Path, track: dict, events: list[dict],
                            from_utc: str | None, to_utc: str | None) -> dict | None:
    final_mxf = Path(track["final_mxf"]).resolve()
    lock_path = Path(str(final_mxf) + ".lock")
    if not lock_path.is_file():
        return None
    try:
        lock = _read_json(lock_path)
        if lock.get("state") != "RECORDING_LOCKED" or not lock.get("read_safe"):
            return None
        if track.get("file_id") and str(lock.get("file_id") or "") != str(track.get("file_id")):
            return None
        committed_position_ns = int(lock.get("committed_position_ns") or 0)
        flushed_bytes = int(lock.get("flushed_bytes") or 0)
        if committed_position_ns <= 0 or flushed_bytes <= 0:
            return None
        partial = Path(str(lock.get("partial_path") or "")).resolve()
        allowed = partial.parent == run.resolve() or partial.is_relative_to((ROOT / "recordings").resolve())
        if not allowed or not partial.is_file():
            return None
        flushed_bytes = min(flushed_bytes, partial.stat().st_size)
        window_start = parse_utc(str(lock["recording_window_start_utc"]))
        confirmed_end = window_start + timedelta(microseconds=committed_position_ns / 1000)
        if not _range_overlaps(window_start, confirmed_end, from_utc, to_utc):
            return None
        matching = _matching_events(track, events)
        intervals = _media_intervals(matching, confirmed_end)
        if not intervals:
            return None
        return {
            "run": run,
            "mxf": partial,
            "final_mxf": final_mxf,
            "track": track,
            "intervals": intervals,
            "open": True,
            "lock": lock,
            "window_start_utc": iso(window_start),
            "confirmed_until_utc": iso(confirmed_end),
            "committed_position_ns": committed_position_ns,
            "flushed_bytes": flushed_bytes,
            "commit_generation": int(lock.get("commit_generation") or 0),
            "commit_lag_target_ms": int(lock.get("commit_lag_target_ms") or 0),
        }
    except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError):
        return None


def _load_closed_candidate(run: Path, track: dict, events: list[dict],
                           from_utc: str | None, to_utc: str | None) -> dict | None:
    mxf = Path(track["final_mxf"]).resolve()
    allowed = mxf.parent == run.resolve() or mxf.is_relative_to((ROOT / "recordings").resolve())
    if not allowed or mxf.suffix.lower() != ".mxf" or not mxf.is_file():
        return None

    matching = _matching_events(track, events)
    kinds = {event.get("event") for event in matching}
    classic_closed = {"WINDOW_CLOSED_COMPLETE", "MEDIA_COMMIT"}.issubset(kinds)
    file_id = str(track.get("file_id") or "")
    category = str(track.get("category") or "")
    shared_closed = any(
        event.get("event") == "SHARED_MXF_CLOSED_COMPLETE"
        and (
            (file_id and f"file_id={file_id}" in str(event.get("detail") or ""))
            or (category and f"category={category}" in str(event.get("detail") or ""))
        )
        for event in events
    )
    if not classic_closed and not shared_closed:
        return None

    intervals = _media_intervals(matching)
    if not intervals:
        return None
    natural_start = parse_utc(intervals[0]["start_utc"])
    natural_end = parse_utc(intervals[-1]["end_utc"])
    if not _range_overlaps(natural_start, natural_end, from_utc, to_utc):
        return None
    return {"run": run, "mxf": mxf, "track": track, "intervals": intervals, "open": False}


def resolve_operational_track(
    logical_track_uuid: str,
    from_utc: str | None = None,
    to_utc: str | None = None,
) -> dict:
    candidates = _candidate_tracks(logical_track_uuid)

    # Prefer the current growing file when the requested range overlaps its
    # confirmed prefix. Historical requests naturally fall through to closed MXFs.
    for run, track, events in candidates:
        growing = _load_growing_candidate(run, track, events, from_utc, to_utc)
        if growing:
            return growing

    for run, track, events in candidates:
        closed = _load_closed_candidate(run, track, events, from_utc, to_utc)
        if closed:
            return closed

    raise LookupError(f"No confirmed operational MXF found for LogicalTrackUUID {logical_track_uuid}")


def build_operational_plan(logical_track_uuid: str, from_utc: str | None = None, to_utc: str | None = None) -> dict:
    resolved = resolve_operational_track(logical_track_uuid, from_utc, to_utc)
    intervals = resolved["intervals"]
    natural_from = parse_utc(intervals[0]["start_utc"])
    natural_to = parse_utc(intervals[-1]["end_utc"])
    start = parse_utc(from_utc) if from_utc else natural_from
    end = parse_utc(to_utc) if to_utc else natural_to
    if resolved.get("open") and resolved.get("confirmed_until_utc"):
        end = min(end, parse_utc(resolved["confirmed_until_utc"]))
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
        "source_scope": "growing_mxf_confirmed" if resolved.get("open") else "closed_operational_mxf_recorder_audit",
        "open": bool(resolved.get("open")),
        "presentation_only": bool(resolved.get("open")),
        "confirmed_until_utc": resolved.get("confirmed_until_utc"),
        "commit_generation": resolved.get("commit_generation"),
        "commit_lag_target_ms": resolved.get("commit_lag_target_ms"),
        "logical_track_uuid": str(track["logical_track_uuid"]),
        "track_instance_uuid": str(track["track_instance_uuid"]),
        "service_id": str(track.get("service_id", "")),
        "endpoint_id": str(track.get("endpoint_id", "")),
        "service_type": str(track.get("service_type", "radio")),
        "track_index": int(track.get("track_index", 0)),
        "mxf_path": str(resolved["mxf"]),
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


def _decode_alaw_byte(value: int) -> int:
    value ^= 0x55
    magnitude = (value & 0x0F) << 4
    segment = (value & 0x70) >> 4
    if segment == 0:
        magnitude += 8
    elif segment == 1:
        magnitude += 0x108
    else:
        magnitude += 0x108
        magnitude <<= segment - 1
    return magnitude if value & 0x80 else -magnitude


ALAW_PCM_BYTES = tuple(struct.pack("<h", _decode_alaw_byte(value)) for value in range(256))


def _read_ber_length(stream, remaining: int) -> tuple[int, int] | None:
    if remaining < 1:
        return None
    first_raw = stream.read(1)
    if len(first_raw) != 1:
        return None
    first = first_raw[0]
    if not (first & 0x80):
        return first, 1
    octets = first & 0x7F
    if octets == 0 or octets > 8 or remaining < 1 + octets:
        return None
    encoded = stream.read(octets)
    if len(encoded) != octets:
        return None
    return int.from_bytes(encoded, "big"), 1 + octets


def _is_target_audio_klv(key: bytes, track_index: int) -> bool:
    return (
        len(key) == 16
        and key[:12] == GC_ESSENCE_PREFIX
        and key[12] == 0x16
        and key[14] in (0x08, 0x09, 0x0A)
        and key[15] == track_index + 1
    )


def _decode_growing_window(resolved: dict, start: datetime, end: datetime) -> bytes:
    window_start = parse_utc(resolved["window_start_utc"])
    if end <= start:
        return b""

    total_samples = max(0, int(round((end - start).total_seconds() * SAMPLE_RATE)))
    output = bytearray(total_samples * BYTES_PER_SAMPLE)
    if total_samples == 0:
        return bytes(output)

    request_start_sample = int(round((start - window_start).total_seconds() * SAMPLE_RATE))
    request_end_sample = request_start_sample + total_samples
    confirmed_samples = int(resolved["committed_position_ns"] * SAMPLE_RATE // 1_000_000_000)
    target_track = int(resolved["track"].get("track_index", 0))
    limit = int(resolved["flushed_bytes"])
    unit_index = 0

    with Path(resolved["mxf"]).open("rb") as stream:
        offset = 0
        while offset + 17 <= limit:
            key = stream.read(16)
            if len(key) != 16:
                break
            offset += 16
            decoded = _read_ber_length(stream, limit - offset)
            if decoded is None:
                break
            value_length, ber_size = decoded
            offset += ber_size
            if value_length < 0 or value_length > limit - offset:
                break

            target = _is_target_audio_klv(key, target_track)
            if not target:
                stream.seek(value_length, 1)
                offset += value_length
                continue

            unit_start_sample = unit_index * SAMPLES_PER_EDIT_UNIT
            unit_index += 1
            if unit_start_sample >= confirmed_samples:
                break

            payload = stream.read(value_length)
            if len(payload) != value_length:
                break
            offset += value_length

            unit_end_sample = min(unit_start_sample + SAMPLES_PER_EDIT_UNIT, confirmed_samples)
            overlap_start = max(unit_start_sample, request_start_sample)
            overlap_end = min(unit_end_sample, request_end_sample)
            if overlap_end <= overlap_start or not payload:
                if unit_start_sample >= request_end_sample:
                    break
                continue

            decoded_pcm = b"".join(ALAW_PCM_BYTES[value] for value in payload[:SAMPLES_PER_EDIT_UNIT])
            available_samples = len(decoded_pcm) // BYTES_PER_SAMPLE
            source_from = overlap_start - unit_start_sample
            source_to = min(overlap_end - unit_start_sample, available_samples)
            if source_to > source_from:
                target_from = overlap_start - request_start_sample
                chunk = decoded_pcm[source_from * 2:source_to * 2]
                output[target_from * 2:target_from * 2 + len(chunk)] = chunk

            if unit_start_sample >= request_end_sample:
                break

    return bytes(output)


def _ffmpeg() -> str:
    command = shutil.which("ffmpeg")
    if not command:
        raise RuntimeError("FFmpeg was not found in PATH")
    return command


def _decode_pcm(mxf: Path, track_index: int = 0) -> bytes:
    if track_index < 0:
        raise ValueError("track_index must be >= 0")
    proc = subprocess.run(
        [_ffmpeg(), "-hide_banner", "-loglevel", "error", "-i", str(mxf),
         "-map", f"0:a:{track_index}", "-ac", "1", "-ar", str(SAMPLE_RATE), "-c:a", "pcm_s16le", "-f", "s16le", "-"],
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
    resolved = resolve_operational_track(logical_track_uuid, from_utc, to_utc)
    plan = build_operational_plan(logical_track_uuid, from_utc, to_utc)
    start = parse_utc(plan["from_utc"])
    end = parse_utc(plan["to_utc"])
    total_ms = (end - start).total_seconds() * 1000
    total_bytes = int(round(total_ms * BYTES_PER_MS))
    if total_bytes % 2:
        total_bytes += 1

    if resolved.get("open"):
        pcm = _decode_growing_window(resolved, start, end)
        return plan, _wav_bytes(pcm)

    cache_key = hashlib.sha256(
        (str(resolved["mxf"]) + "|" + str(resolved["track"].get("track_index", 0))
         + "|" + plan["from_utc"] + "|" + plan["to_utc"]
         + "|" + str(resolved["mxf"].stat().st_mtime_ns)).encode("utf-8")
    ).hexdigest()
    CACHE.mkdir(parents=True, exist_ok=True)
    cache_path = CACHE / f"{cache_key}.wav"
    if cache_path.is_file():
        return plan, cache_path.read_bytes()

    decoded = _decode_pcm(resolved["mxf"], int(resolved["track"].get("track_index", 0)))
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
