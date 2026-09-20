"""Local RC1 historical player API. Closed MXFs only; no partial/live evidence."""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import re
import shutil
import sqlite3
import subprocess
import sys
import uuid
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from timeline_data import build_timeline


ROOT = Path(__file__).resolve().parents[2]
WEB = ROOT / "web" / "player"
RUNS = ROOT / "runs" / "web-player-runtime"
CACHE = ROOT / "runs" / "web-player-cache"
CACHE_TTL_SECONDS = 7 * 24 * 60 * 60
UUID_RE = re.compile(r"^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$")
UTC_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$")
PLANS: dict[str, Path] = {}
EXPORTS: dict[str, Path] = {}


def cache_file(*parts: str, suffix: str = ".wav") -> Path:
    key = hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()
    return CACHE / f"{key}{suffix}"


def prune_cache() -> None:
    CACHE.mkdir(parents=True, exist_ok=True)
    cutoff = __import__("time").time() - CACHE_TTL_SECONDS
    for item in CACHE.iterdir():
        try:
            if item.is_file() and item.stat().st_mtime < cutoff:
                item.unlink()
        except OSError:
            pass


def ensure_plan_export(plan_path: Path, mode: str) -> tuple[Path, dict, bool]:
    with plan_path.open("rb") as source:
        plan_hash = hashlib.file_digest(source, "sha256").hexdigest()
    cached_wav = cache_file("export", plan_hash, mode)
    cached_manifest = cached_wav.with_suffix(".json")
    cache_hit = cached_wav.is_file() and cached_manifest.is_file() and cached_wav.stat().st_size > 44
    if cache_hit:
        manifest = json.loads(cached_manifest.read_text(encoding="utf-8"))
    else:
        token = uuid.uuid4().hex
        out = RUNS / token
        invoke_ps("scripts/playback/Invoke-RealPlaybackSegmentExport.ps1", ["-PlanPath", str(plan_path), "-Mode", mode, "-OutDir", str(out)])
        manifest = json.loads((out / "export-manifest.json").read_text(encoding="utf-8-sig"))
        if manifest.get("result") == "PASS":
            cached_wav.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(out / "export.wav", cached_wav)
            cached_manifest.write_text(json.dumps(manifest, ensure_ascii=False), encoding="utf-8")
    if manifest.get("result") != "PASS" or manifest.get("source_scope") != "real_closed_mxf_verified_track_decode":
        raise RuntimeError("Exportação não validou MXF fechado e identidade.")
    return cached_wav, manifest, cache_hit


def latest_index() -> Path:
    candidates = sorted((ROOT / "runs" / "index").glob("temporal-index-*/recorder-index.sqlite"), reverse=True)
    if not candidates:
        raise RuntimeError("Nenhum índice SQLite executado está disponível.")
    return candidates[0]


def process_alive(pid: int) -> bool:
    kernel = ctypes.windll.kernel32
    handle = kernel.OpenProcess(0x1000, False, pid)
    if not handle:
        return False
    try:
        code = ctypes.c_ulong()
        return bool(kernel.GetExitCodeProcess(handle, ctypes.byref(code))) and code.value == 259
    finally:
        kernel.CloseHandle(handle)


def services() -> list[dict]:
    db = latest_index()
    uri = f"file:{db.as_posix()}?mode=ro"
    with sqlite3.connect(uri, uri=True) as con:
        con.row_factory = sqlite3.Row
        rows = con.execute("SELECT logical_track_uuid,service_type,service_id,endpoint_id,media_flow,display_name FROM logical_track ORDER BY service_type,service_id,endpoint_id").fetchall()
    return [dict(row) for row in rows]


def catalog() -> list[dict]:
    """Show observed tracks from the index and executed runs, with provenance."""
    entries: dict[str, dict] = {}

    def add(track: str, *, endpoint: str, service: str, service_type: str, name: str,
            component: str, occurrence: dict, indexed: bool = False) -> None:
        row = entries.setdefault(track, {
            "logical_track_uuid": track, "endpoint_id": endpoint, "service_id": service,
            "service_type": service_type, "display_name": name, "media_flow": "mono",
            "component": component, "indexed": False, "occurrences": [],
        })
        row["indexed"] = row["indexed"] or indexed
        row["occurrences"].append(occurrence)

    db = latest_index()
    with sqlite3.connect(f"file:{db.as_posix()}?mode=ro", uri=True) as con:
        con.row_factory = sqlite3.Row
        rows = con.execute("""SELECT lt.logical_track_uuid,lt.endpoint_id,lt.service_id,lt.service_type,lt.display_name,
            ti.track_instance_uuid,ti.track_index,rf.file_id,rf.relative_path,rf.state,rf.segment_sequence
            FROM logical_track lt JOIN track_instance ti ON ti.logical_track_uuid=lt.logical_track_uuid
            JOIN recording_file rf ON rf.file_id=ti.file_id
            ORDER BY rf.recording_window_start_utc,rf.segment_sequence""").fetchall()
    for item in rows:
        row = dict(item)
        path = ROOT / row["relative_path"]
        add(row["logical_track_uuid"], endpoint=row["endpoint_id"], service=row["service_id"],
            service_type=row["service_type"], name=row["display_name"], component="cwp_indexed_legacy",
            occurrence={"track_instance_uuid": row["track_instance_uuid"], "track_index": row["track_index"],
                        "file_id": row["file_id"], "path": str(path), "run": "SQLite RC1 / Phase 7",
                        "state": row["state"] if path.is_file() else "MISSING_FILE", "tone_hz": None}, indexed=True)

    for report_path in sorted((ROOT / "runs" / "phase9-service-perspective-matrix").glob("*/service-perspective-matrix-report.json")):
        try:
            report = json.loads(report_path.read_text(encoding="utf-8-sig"))
        except (OSError, json.JSONDecodeError):
            continue
        if report.get("result") != "PASS":
            continue
        tones = {tone["track_instance_uuid"]: tone["expected_hz"] for tone in report.get("tone_validation", [])}
        for row in report.get("expectations", []):
            if not row.get("track_instance_uuid"):
                continue  # Early reports did not retain physical identity in this field.
            file = Path(row["final_mxf"])
            if not file.is_file():
                continue
            endpoint = row["endpoint_id"]
            component = ("gateway_matrix" if endpoint.startswith("GATEWAY-") else
                         "cwp_capacity" if row["service_id"].startswith("STRESS-") else "cwp_direct")
            add(row["logical_track_uuid"], endpoint=endpoint, service=row["service_id"],
                service_type=row["service_type"], name=f"{row['service_id']} · {endpoint}",
                component=component, occurrence={"track_instance_uuid": row["track_instance_uuid"],
                    "track_index": 0, "file_id": None, "path": str(file), "run": report_path.parent.name,
                    "state": "CLOSED_COMPLETE", "tone_hz": tones.get(row["track_instance_uuid"])})

    for report_path in sorted((ROOT / "runs" / "phase8-recording-gateway").glob("*/phase8-recording-gateway-report.json")):
        try:
            row = json.loads(report_path.read_text(encoding="utf-8-sig"))
        except (OSError, json.JSONDecodeError):
            continue
        file = Path(row.get("final_mxf", ""))
        if row.get("result") != "PASS" or not file.is_file():
            continue
        add(row["logical_track_uuid"], endpoint="GATEWAY-SIP-01", service="TEL-01",
            service_type="telephone", name="TEL-01 · Gateway SIP", component="gateway_sip",
            occurrence={"track_instance_uuid": row["track_instance_uuid"], "track_index": 0,
                "file_id": None, "path": str(file), "run": report_path.parent.name,
                "state": "CLOSED_COMPLETE", "tone_hz": None})

    for state_path in sorted((ROOT / "runs" / "operational-recorder").glob("*/operational-recorder-state.json")):
        try:
            row = json.loads(state_path.read_text(encoding="utf-8-sig"))
            alive = process_alive(int(row["pid"]))
            final = Path(row["final_mxf"])
            partial = Path(row["partial_mxf"])
            file = final if final.is_file() else partial
            state = "CLOSED_COMPLETE" if final.is_file() else "ARMED_PARTIAL" if alive and partial.is_file() else "STOPPED_OR_INCOMPLETE"
            add(row["logical_track_uuid"], endpoint=row["endpoint_id"], service=row["service_id"],
                service_type="radio", name=f"{row['service_id']} · {row['endpoint_id']}",
                component="cwp_operational", occurrence={"track_instance_uuid": row["track_instance_uuid"],
                    "track_index": 0, "file_id": None, "path": str(file), "run": Path(row["run_dir"]).name,
                    "state": state, "tone_hz": None})
        except (OSError, ValueError, KeyError, json.JSONDecodeError):
            pass

    result = list(entries.values())
    for row in result:
        row["occurrences"].sort(key=lambda item: (item["run"], item["track_instance_uuid"]), reverse=True)
        row["status"] = ("INDEXED" if row["indexed"] else
                         "ARMED_NO_EVIDENCE" if any(x["state"] == "ARMED_PARTIAL" for x in row["occurrences"]) else
                         "CLOSED_NOT_INDEXED" if any(x["state"] == "CLOSED_COMPLETE" for x in row["occurrences"]) else
                         "INCOMPLETE")
        row["physical_track_count"] = len(row["occurrences"])
    return sorted(result, key=lambda row: (row["component"], row["endpoint_id"], row["service_id"]))


def invoke_ps(script: str, args: list[str]) -> None:
    cmd = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(ROOT / script), *args]
    result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=120)
    if result.returncode:
        raise RuntimeError(f"{script} exit={result.returncode}: {result.stderr.strip() or result.stdout.strip()}")


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB), **kwargs)

    def send_json(self, obj: object, code: int = 200) -> None:
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def fail(self, exc: Exception, code: int = 400) -> None:
        self.send_json({"error": str(exc)}, code)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/timeline":
            try:
                query = parse_qs(parsed.query)
                self.send_json(build_timeline(query.get("date", [None])[0], query.get("start", [None])[0]))
            except Exception as exc:
                self.fail(exc)
            return
        if parsed.path == "/health":
            try:
                self.send_json({"status": "ok", "scope": "historical_closed_mxf", "index": str(latest_index()),
                                "live_tap": False, "frontend_available": (WEB / "index.html").is_file()})
            except Exception as exc:
                self.fail(exc, 503)
            return
        if parsed.path == "/api/services":
            try:
                self.send_json({"services": services(), "scope": "sqlite_temporal_index_from_closed_mxf"})
            except Exception as exc:
                self.fail(exc, 503)
            return
        if parsed.path == "/api/live":
            try:
                pointer = ROOT / "runs" / "operational-recorder" / "current-run.txt"
                run_dir = Path(pointer.read_text(encoding="utf-8").lstrip("\ufeff").strip()) if pointer.is_file() else None
                state_path = run_dir / "operational-recorder-state.json" if run_dir else None
                audit_path = run_dir / "recorder-audit.jsonl" if run_dir else None
                state = json.loads(state_path.read_text(encoding="utf-8-sig")) if state_path and state_path.is_file() else {}
                events = []
                if audit_path and audit_path.is_file():
                    lines = audit_path.read_text(encoding="utf-8", errors="replace").splitlines()[-200:]
                    for line in lines:
                        try: events.append(json.loads(line))
                        except json.JSONDecodeError: pass
                self.send_json({"scope":"live_preview_only", "process_alive": bool(state.get("pid") and process_alive(int(state["pid"]))),
                                "run": str(run_dir) if run_dir else None, "events": events,
                                "live_buffer_available": bool(state.get("live_buffer_available", False)),
                                "evidence": False})
            except Exception as exc:
                self.fail(exc, 503)
            return
        if parsed.path == "/api/catalog":
            try:
                rows = catalog()
                self.send_json({"schema": "recorder-poc.player-track-catalog.v1", "tracks": rows,
                                "counts": {"logical_tracks": len(rows), "physical_occurrences": sum(len(x["occurrences"]) for x in rows),
                                           "indexed": sum(x["indexed"] for x in rows)},
                                "scope": "executed_run_reports_and_sqlite_index"})
            except Exception as exc:
                self.fail(exc, 503)
            return
        if parsed.path == "/api/plan":
            try:
                query = parse_qs(parsed.query)
                track = query.get("logical_track_uuid", [""])[0]
                start = query.get("from_utc", [""])[0]
                end = query.get("to_utc", [""])[0]
                if not UUID_RE.fullmatch(track) or track not in {s["logical_track_uuid"] for s in services()}:
                    raise ValueError("LogicalTrackUUID não pertence ao índice atual.")
                if (start and not UTC_RE.fullmatch(start)) or (end and not UTC_RE.fullmatch(end)):
                    raise ValueError("Use UTC ISO, por exemplo 2026-09-19T17:12:11.586Z.")
                token = uuid.uuid4().hex
                out = RUNS / token
                out.mkdir(parents=True, exist_ok=False)
                args = ["-IndexPath", str(latest_index()), "-LogicalTrackUuid", track, "-OutDir", str(out), "-Mode", "continuous"]
                if start:
                    args += ["-FromUtc", start]
                if end:
                    args += ["-ToUtc", end]
                invoke_ps("scripts/playback/Invoke-HistoricalPlaybackPlan.ps1", args)
                path = out / "historical-playback-plan.json"
                plan = json.loads(path.read_text(encoding="utf-8-sig"))
                if plan.get("source_scope") != "sqlite_temporal_index_from_closed_mxf":
                    raise RuntimeError("Plano sem origem SQLite/MXF fechado.")
                PLANS[token] = path
                self.send_json({"plan_id": token, "plan": plan, "services": services(), "scope": "historical_closed_mxf"})
            except Exception as exc:
                self.fail(exc)
            return
        if parsed.path.startswith("/api/audio/"):
            token = parsed.path.removeprefix("/api/audio/")
            wav = EXPORTS.get(token)
            if not wav or not wav.is_file():
                self.send_error(404, "WAV indisponível")
                return
            self.send_response(200)
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(wav.stat().st_size))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            with wav.open("rb") as source:
                while chunk := source.read(65536):
                    self.wfile.write(chunk)
            return
        if parsed.path.startswith("/api/"):
            self.send_error(404)
            return
        super().do_GET()

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        if path not in ("/api/export", "/api/preview", "/api/mix"):
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length < 1 or length > 4096:
                raise ValueError("Corpo de requisição inválido.")
            request = json.loads(self.rfile.read(length))
            if path == "/api/preview":
                track = request.get("logical_track_uuid", "")
                instance = request.get("track_instance_uuid", "")
                matches = [item for row in catalog() if row["logical_track_uuid"] == track
                           for item in row["occurrences"] if item["track_instance_uuid"] == instance]
                if len(matches) != 1 or matches[0]["state"] != "CLOSED_COMPLETE":
                    raise ValueError("Instância MXF fechada não encontrada no catálogo.")
                item = matches[0]
                mxf = Path(item["path"]).resolve()
                if not mxf.is_relative_to((ROOT / "runs").resolve()) or mxf.suffix.lower() != ".mxf":
                    raise ValueError("Origem MXF fora das gravações executadas.")
                with mxf.open("rb") as source:
                    source_hash = hashlib.file_digest(source, "sha256").hexdigest()
                probe = subprocess.run(["ffprobe.exe", "-v", "error", "-show_entries",
                    "stream=index,codec_name,channels,sample_rate:stream_tags=track_name", "-of", "json", str(mxf)],
                    capture_output=True, text=True, timeout=30, cwd=ROOT)
                if probe.returncode:
                    raise RuntimeError(f"ffprobe falhou: {probe.stderr.strip()}")
                streams = [s for s in json.loads(probe.stdout).get("streams", []) if s.get("index") == item["track_index"]]
                if len(streams) != 1:
                    raise RuntimeError("TrackIndex não encontrado no MXF.")
                stream = streams[0]
                track_name = stream.get("tags", {}).get("track_name", "")
                if (stream.get("codec_name") != "pcm_alaw" or stream.get("channels") != 1 or
                    int(stream.get("sample_rate", 0)) != 8000 or
                    f"LT={track}" not in track_name or f"TI={instance}" not in track_name):
                    raise RuntimeError("Codec mono ou LT/TI embutidos não conferem com a trilha selecionada.")
                cached = cache_file("preview", source_hash, str(item["track_index"]), track, instance)
                cached.parent.mkdir(parents=True, exist_ok=True)
                cache_hit = cached.is_file() and cached.stat().st_size > 44
                if not cache_hit:
                    temp = cached.with_suffix(".tmp.wav")
                    decoded = subprocess.run(["ffmpeg.exe", "-y", "-v", "error", "-i", str(mxf),
                        "-map", f"0:{item['track_index']}", "-ac", "1", "-ar", "8000", "-c:a", "pcm_s16le", str(temp)],
                        capture_output=True, text=True, timeout=60, cwd=ROOT)
                    if decoded.returncode or not temp.is_file() or temp.stat().st_size <= 44:
                        temp.unlink(missing_ok=True)
                        raise RuntimeError(f"Decodificação MXF falhou: {decoded.stderr.strip()}")
                    temp.replace(cached)
                token = uuid.uuid4().hex
                wav = cached
                EXPORTS[token] = wav
                with wav.open("rb") as source:
                    wav_hash = hashlib.file_digest(source, "sha256").hexdigest()
                self.send_json({"audio_url": f"/api/audio/{token}", "scope": "closed_mxf_technical_preview",
                    "recorded_evidence_bundle": False, "logical_track_uuid": track, "track_instance_uuid": instance,
                    "track_index": item["track_index"], "mxf_sha256": source_hash,
                    "wav_sha256": wav_hash, "wav_bytes": wav.stat().st_size,
                    "cache": {"hit": cache_hit, "key_scope": "mxf_sha256+track_index+LT+TI"}})
                return
            if path == "/api/mix":
                plan_ids = request.get("plan_ids", [])
                mode = request.get("mode", "only_audio")
                if mode not in ("only_audio", "continuous") or not isinstance(plan_ids, list) or not 2 <= len(plan_ids) <= 16 or len(set(plan_ids)) != len(plan_ids):
                    raise ValueError("Mix requer de 2 a 16 planos e modo only_audio ou continuous.")
                exports = [ensure_plan_export(PLANS[plan_id], mode) for plan_id in plan_ids if plan_id in PLANS]
                if len(exports) != len(plan_ids):
                    raise ValueError("Um ou mais planos do mix não estão disponíveis.")
                key = ["mix", mode, *sorted(plan_ids)]
                mixed = cache_file(*key)
                cache_hit = mixed.is_file() and mixed.stat().st_size > 44
                if not cache_hit:
                    inputs = []
                    for index, (wav, _manifest, _hit) in enumerate(exports):
                        inputs.extend(["-i", str(wav)])
                    temp = mixed.with_suffix(".tmp.wav")
                    mixed.parent.mkdir(parents=True, exist_ok=True)
                    decoded = subprocess.run(["ffmpeg.exe", "-y", "-v", "error", *inputs,
                        "-filter_complex", f"amix=inputs={len(exports)}:duration=longest:normalize=0", "-ac", "1", "-ar", "8000", "-c:a", "pcm_s16le", str(temp)],
                        capture_output=True, text=True, timeout=120, cwd=ROOT)
                    if decoded.returncode or not temp.is_file() or temp.stat().st_size <= 44:
                        temp.unlink(missing_ok=True)
                        raise RuntimeError(f"Mixagem falhou: {decoded.stderr.strip()}")
                    temp.replace(mixed)
                token = uuid.uuid4().hex
                EXPORTS[token] = mixed
                self.send_json({"audio_url": f"/api/audio/{token}", "scope": "verified_historical_track_mix",
                                "plan_ids": plan_ids, "mode": mode, "track_count": len(exports),
                                "evidence_chain_complete": False, "cache": {"hit": cache_hit, "key_scope": "plan_ids+mode"}})
                return
            plan_id = request.get("plan_id", "")
            mode = request.get("mode", "only_audio")
            if mode not in ("only_audio", "continuous") or plan_id not in PLANS:
                raise ValueError("Plano ou modo indisponível.")
            cached_wav, manifest, cache_hit = ensure_plan_export(PLANS[plan_id], mode)
            token = uuid.uuid4().hex
            EXPORTS[token] = cached_wav
            self.send_json({"audio_url": f"/api/audio/{token}", "manifest": manifest, "evidence_chain_complete": False,
                            "cache": {"hit": cache_hit, "key_scope": "plan_sha256+mode"}})
        except Exception as exc:
            self.fail(exc)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    RUNS.mkdir(parents=True, exist_ok=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    prune_cache()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"HISTORICAL PLAYER READY http://127.0.0.1:{args.port}/", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
