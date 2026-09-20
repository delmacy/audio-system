"""Local HTTP boundary for timeline and operational playback."""

from __future__ import annotations

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from playback_data import build_operational_plan, render_operational_wav
from timeline_data import build_timeline

HOST = "127.0.0.1"
PORT = 8500


class Handler(BaseHTTPRequestHandler):
    server_version = "AudioSystemTimelineApi/0.2"

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
                    "/api/playback/plan?lt=<uuid>&from=<utc>&to=<utc>",
                    "/api/playback/audio?lt=<uuid>&from=<utc>&to=<utc>",
                ],
            })
            return

        if parsed.path == "/api/health":
            self._json(200, {"status": "ok", "service": "timeline-api"})
            return

        if parsed.path == "/api/timeline":
            query = parse_qs(parsed.query)
            date = query.get("date", [None])[0]
            start = query.get("start", [None])[0]
            try:
                self._json(200, build_timeline(date=date, start=start))
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

    def log_message(self, fmt: str, *args: object) -> None:
        print(f"[timeline-api] {self.address_string()} - {fmt % args}")


class TimelineHttpServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    print(f"Audio System timeline/playback API listening on http://{HOST}:{PORT}")
    TimelineHttpServer((HOST, PORT), Handler).serve_forever()
