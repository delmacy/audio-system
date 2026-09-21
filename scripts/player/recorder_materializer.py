"""Materialize the live recorder session map and topology manifest."""

from __future__ import annotations

import argparse
import json
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path

from config_store import get_topology_revision, list_cwps, list_services
from recording_layout import ROOT, recording_window_bounds, recording_window_paths

IDENTITY_NAMESPACE = uuid.UUID("d7ca84d3-730d-42f6-87bb-fb5c7f9874e6")


def _utc(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _service_number(label: str) -> str:
    matches = re.findall(r"\d+(?:\.\d+)*", label)
    if not matches:
        raise ValueError(f"Service label has no ramal/frequency number: {label}")
    return re.sub(r"\D", "", matches[-1])


def _logical_uuid(canonical: str) -> str:
    return str(uuid.uuid5(IDENTITY_NAMESPACE, canonical))


def _existing_segment_sequence(paths: dict[str, dict]) -> int:
    highest = -1
    for item in paths.values():
        base = Path(item["file"])
        if base.exists() or Path(item["partial"]).exists() or Path(item["lock"]).exists():
            highest = max(highest, 0)
        stem = base.stem
        for candidate in base.parent.glob(stem + ".seg*.mxf"):
            match = re.search(r"\.seg(\d+)\.mxf$", candidate.name)
            if match:
                highest = max(highest, int(match.group(1)))
    return highest + 1


def _window_targets() -> tuple[dict[str, dict], int]:
    base = recording_window_paths()
    sequence = _existing_segment_sequence(base)
    if sequence == 0:
        return base, 0

    result: dict[str, dict] = {}
    for kind, item in base.items():
        original = Path(item["file"])
        final = original.with_name(f"{original.stem}.seg{sequence:03d}.mxf")
        result[kind] = {
            **item,
            "file": str(final),
            "file_name": final.name,
            "partial": str(final) + ".partial",
            "lock": str(final) + ".lock",
        }
    return result, sequence


def _track(
    *,
    category: str,
    service_type: str,
    service_id: str,
    endpoint_id: str,
    route_key: str,
    activity_signal: str,
    role: str | None = None,
    slot_index: int | None = None,
) -> dict:
    role_part = f"|role={role}|slot={slot_index}" if role else ""
    canonical = (
        f"identity-v2|category={category}|service_type={service_type}|service_id={service_id}"
        f"|endpoint_id={endpoint_id}|media_flow=mono{role_part}"
    )
    logical = _logical_uuid(canonical)
    instance = str(uuid.uuid4())
    display = f"{category.upper()} {service_id}"
    if role:
        display += f" {role.upper()} SLOT {slot_index}"
    return {
        "category": category,
        "service_type": service_type,
        "service_id": service_id,
        "endpoint_id": endpoint_id,
        "route_key": route_key,
        "activity_signal": activity_signal,
        "role": role,
        "slot_index": slot_index,
        "canonical_identity": canonical,
        "logical_track_uuid": logical,
        "track_instance_uuid": instance,
        "display_name": display,
    }


def build_topology() -> dict:
    from recording_layout import get_recorder_settings

    settings = get_recorder_settings()
    cwps = list_cwps()
    services = list_services()
    paths, segment_sequence = _window_targets()
    now = datetime.now(timezone.utc)
    window_start_local, window_end_local = recording_window_bounds()
    window_start = window_start_local.astimezone(timezone.utc)
    window_end = window_end_local.astimezone(timezone.utc)
    file_ids = {
        kind: str(uuid.uuid5(IDENTITY_NAMESPACE, f"file|{Path(item['file']).as_posix()}"))
        for kind, item in paths.items()
    }

    tracks: list[dict] = []

    for cwp in sorted(cwps, key=lambda item: (item["side"], item["label"])):
        label = str(cwp["label"])
        tracks.append(_track(
            category="cwp",
            service_type="cwp",
            service_id=label,
            endpoint_id=label,
            route_key=f"/record/{label}/cwp-rx",
            activity_signal="none",
        ))

    for service in sorted((item for item in services if item["kind"] == "RADIO"), key=lambda item: item["label"]):
        number = _service_number(str(service["label"]))
        tracks.append(_track(
            category="radio",
            service_type="radio",
            service_id=number,
            endpoint_id="RADIO-BUS",
            route_key=f"/record/radio/{number}",
            activity_signal="squ",
        ))

    received = int(settings["telephone"]["received_slots_per_phone"])
    calling = int(settings["telephone"]["calling_slots_per_phone"])
    for service in sorted((item for item in services if item["kind"] == "TEL"), key=lambda item: item["label"]):
        number = _service_number(str(service["label"]))
        for slot in range(1, received + 1):
            tracks.append(_track(
                category="telephone",
                service_type="telephone",
                service_id=number,
                endpoint_id=str(service["label"]),
                route_key=f"/record/telephone/{number}/received/{slot:02d}",
                activity_signal="none",
                role="received",
                slot_index=slot,
            ))
        for slot in range(1, calling + 1):
            tracks.append(_track(
                category="telephone",
                service_type="telephone",
                service_id=number,
                endpoint_id=str(service["label"]),
                route_key=f"/record/telephone/{number}/calling/{slot:02d}",
                activity_signal="none",
                role="calling",
                slot_index=slot,
            ))

    rtp_port = 20000
    session_rows = []
    category_track_index = {"cwp": 0, "radio": 0, "telephone": 0}
    files = {}
    for kind in ("cwp", "radio", "telephone"):
        category_tracks = [track for track in tracks if track["category"] == kind]
        if not category_tracks:
            continue
        files[kind] = {
            "category": kind,
            "file_id": file_ids[kind],
            "path": paths[kind]["file"],
            "relative_path": str(Path(paths[kind]["file"]).resolve().relative_to(ROOT.resolve())).replace("\\", "/"),
            "partial": paths[kind]["partial"],
            "lock": paths[kind]["lock"],
            "segment_sequence": segment_sequence,
            "recording_window_start_utc": _utc(window_start),
            "recording_window_end_utc": _utc(window_end),
            "track_count": len(category_tracks),
        }

    for track in tracks:
        kind = track["category"]
        file = files[kind]
        track_index = category_track_index[kind]
        category_track_index[kind] += 1
        track["track_index"] = track_index
        track["file_id"] = file["file_id"]
        track["final_mxf"] = file["path"]
        track["mxf_name"] = Path(file["path"]).name
        track["rtp_port"] = rtp_port
        rtp_port += 1
        if rtp_port > 29999:
            raise ValueError("Recorder RTP allocation exceeded configured 20000-29999 range")
        session_rows.append({
            "route_key": track["route_key"],
            "endpoint_id": track["endpoint_id"],
            "service_id": track["service_id"],
            "media_flow": "mono",
            "activity_signal": track["activity_signal"],
            "display_name": track["display_name"],
            "logical_uuid": track["logical_track_uuid"],
            "instance_uuid": track["track_instance_uuid"],
            "file_id": file["file_id"],
            "output_partial": file["partial"],
            "output_final": file["path"],
            "lock_path": file["lock"],
            "rtp_port": track["rtp_port"],
            "window_start_utc": file["recording_window_start_utc"],
            "segment_sequence": segment_sequence,
            "session_kind": kind,
        })

    return {
        "schema": "audio-system.recorder-topology.v1",
        "generated_utc": _utc(now),
        "segment_sequence": segment_sequence,
        "settings": settings,
        "topology_revision": get_topology_revision(),
        "window_start_utc": _utc(window_start),
        "window_end_utc": _utc(window_end),
        "files": files,
        "tracks": tracks,
        "sessions": session_rows,
    }


def write_materialization(run_dir: Path) -> dict:
    topology = build_topology()
    run_dir.mkdir(parents=True, exist_ok=True)
    session_map = run_dir / "session-map.tsv"
    manifest = run_dir / "recording-topology.json"

    header = [
        "route_key", "endpoint_id", "service_id", "media_flow", "activity_signal",
        "display_name", "logical_uuid", "instance_uuid", "file_id", "output_partial",
        "output_final", "lock_path", "rtp_port", "window_start_utc",
        "segment_sequence", "session_kind",
    ]
    lines = ["\t".join(header)]
    for row in topology["sessions"]:
        lines.append("\t".join(str(row[key]) for key in header))
    session_map.write_text("\n".join(lines) + "\n", encoding="utf-8")
    manifest.write_text(json.dumps(topology, ensure_ascii=False, indent=2), encoding="utf-8")

    return {
        "session_map": str(session_map),
        "manifest": str(manifest),
        "session_count": len(topology["sessions"]),
        "files": topology["files"],
        "segment_sequence": topology["segment_sequence"],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", required=True)
    args = parser.parse_args()
    result = write_materialization(Path(args.run_dir).resolve())
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
