"""Local HTTP boundary for timeline and operational playback."""

from __future__ import annotations

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from playback_data import build_operational_plan, render_operational_wav
from timeline_data import build_timeline
from config_store import configuration_snapshot, create_cwp, create_service, delete_cwp, delete_service, list_cwps, list_services, next_cwp_ip

HOST = "127.0.0.1"
PORT = 8500


class Handler(BaseHTTPRequestHandler):
    server_version = "AudioSystemTimelineApi/0.3"

    def _send(self, status: int, body: bytes, content_type: str) -> None:
        try:
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionAbortedError, ConnectionResetError):
            return

    def _json(self, status: int, payload: dict) -> None:
        self._send(status, json.dumps(payload, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8")

    def _read_json_body(self) -> dict:
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        if not raw:
            return {}
        payload = json.loads(raw.decode("utf-8"))
        if not isinstance(payload, dict):
            raise ValueError("JSON body must be an object")
        return payload

    def _playback_args(self, parsed) -> tuple[str, str | None, str | None]:
        query = parse_qs(parsed.query)
        lt = query.get("lt", [""])[0]
        if not lt:
            raise ValueError("lt is required")
        return lt, query.get("from", [None])[0], query.get("to", [None])[0]

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)

        if parsed.path == "/":
            self._json(200, {
                "status": "ok",
                "service": "timeline-api",
                "endpoints": [
                    "/api/health",
                    "/api/timeline",
                    "/api/config",
                    "/api/cwps",
                    "/api/services",
                    "/api/network/next-ip",
                    "/api/playback/plan?lt=<uuid>&from=<utc>&to=<utc>",
                    "/api/playback/audio?lt=<uuid>&from=<utc>&to=<utc>",
                ],
            })
            return

        if parsed.path == "/api/health":
            self._json(200, {"status": "ok", "service": "timeline-api"})
            return

        if parsed.path == "/api/config":
            try:
                self._json(200, configuration_snapshot())
            except Exception as exc:
                self._json(500, {"error": "configuration_failed", "detail": str(exc)})
            return

        if parsed.path == "/api/cwps":
            try:
                self._json(200, {"cwps": list_cwps()})
            except Exception as exc:
                self._json(500, {"error": "cwp_list_failed", "detail": str(exc)})
            return

        if parsed.path == "/api/services":
            try:
                self._json(200, {"services": list_services()})
            except Exception as exc:
                self._json(500, {"error": "service_list_failed", "detail": str(exc)})
            return

        if parsed.path == "/api/network/next-ip":
            try:
                self._json(200, {"ip": next_cwp_ip(), "allocation": "first_free_ascending"})
            except Exception as exc:
                self._json(500, {"error": "ip_allocation_failed", "detail": str(exc)})
            return

        if parsed.path == "/api/timeline":
            query = parse_qs(parsed.query)
            date = query.get("date", [None])[0]
            start = query.get("start", [None])[0]
            run = query.get("run", [None])[0]
            try:
                self._json(200, build_timeline(date=date, start=start, run=run))
            except ValueError as exc:
                self._json(400, {"error": "invalid_request", "detail": str(exc)})
            except Exception as exc:
                self._json(500, {"error": "timeline_build_failed", "detail": str(exc)})
            return

        if parsed.path in {"/api/playback/plan", "/api/playback/audio"}:
            try:
                lt, from_utc, to_utc = self._playback_args(parsed)
                if parsed.path == "/api/playback/plan":
                    self._json(200, build_operational_plan(lt, from_utc, to_utc))
                else:
                    plan, wav = render_operational_wav(lt, from_utc, to_utc)
                    self._send(200, wav, "audio/wav")
            except ValueError as exc:
                self._json(400, {"error": "invalid_request", "detail": str(exc)})
            except LookupError as exc:
                self._json(404, {"error": "playback_track_not_found", "detail": str(exc)})
            except Exception as exc:
                self._json(500, {"error": "playback_failed", "detail": str(exc)})
            return

        self._json(404, {"error": "not_found"})


    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        try:
            payload = self._read_json_body()
            if parsed.path == "/api/cwps":
                item = create_cwp(
                    label=str(payload.get("label", "")),
                    side=str(payload.get("side", "A")),
                    ip=str(payload["ip"]) if payload.get("ip") not in (None, "") else None,
                )
                self._json(201, {"cwp": item})
                return
            if parsed.path == "/api/services":
                item = create_service(
                    kind=str(payload.get("kind", "")),
                    label=str(payload.get("label", "")),
                    endpoint=str(payload.get("endpoint", "")),
                )
                self._json(201, {"service": item})
                return
            self._json(404, {"error": "not_found"})
        except ValueError as exc:
            self._json(400, {"error": "invalid_request", "detail": str(exc)})
        except json.JSONDecodeError as exc:
            self._json(400, {"error": "invalid_json", "detail": str(exc)})
        except Exception as exc:
            self._json(500, {"error": "configuration_write_failed", "detail": str(exc)})

    def do_DELETE(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        try:
            if parsed.path.startswith("/api/cwps/"):
                record_id = parsed.path.removeprefix("/api/cwps/")
                if not record_id:
                    raise ValueError("CWP id is required")
                delete_cwp(record_id)
                self._json(200, {"deleted": True, "id": record_id})
                return
            if parsed.path.startswith("/api/services/"):
                record_id = parsed.path.removeprefix("/api/services/")
                if not record_id:
                    raise ValueError("Service id is required")
                delete_service(record_id)
                self._json(200, {"deleted": True, "id": record_id})
                return
            self._json(404, {"error": "not_found"})
        except ValueError as exc:
            self._json(400, {"error": "invalid_request", "detail": str(exc)})
        except LookupError as exc:
            self._json(404, {"error": "not_found", "detail": str(exc)})
        except Exception as exc:
            self._json(500, {"error": "configuration_delete_failed", "detail": str(exc)})

    def log_message(self, fmt: str, *args: object) -> None:
        print(f"[timeline-api] {self.address_string()} - {fmt % args}")


class TimelineHttpServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    print(f"Audio System timeline/playback API listening on http://{HOST}:{PORT}")
    TimelineHttpServer((HOST, PORT), Handler).serve_forever()
