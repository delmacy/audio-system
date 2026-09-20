"""Minimal local HTTP boundary for observed timeline data.

Run from the repository root:
    python scripts/player/timeline_api.py

The frontend Vite dev server proxies /api/* to http://127.0.0.1:8500.
"""

from __future__ import annotations

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from timeline_data import build_timeline

HOST = "127.0.0.1"
PORT = 8500


class Handler(BaseHTTPRequestHandler):
    server_version = "AudioSystemTimelineApi/0.1"

    def _json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)

        if parsed.path == "/api/health":
            self._json(200, {"status": "ok", "service": "timeline-api"})
            return

        if parsed.path != "/api/timeline":
            self._json(404, {"error": "not_found"})
            return

        query = parse_qs(parsed.query)
        date = query.get("date", [None])[0]
        start = query.get("start", [None])[0]

        try:
            payload = build_timeline(date=date, start=start)
        except ValueError as exc:
            self._json(400, {"error": "invalid_request", "detail": str(exc)})
            return
        except Exception as exc:
            self._json(500, {"error": "timeline_build_failed", "detail": str(exc)})
            return

        self._json(200, payload)

    def log_message(self, fmt: str, *args: object) -> None:
        print(f"[timeline-api] {self.address_string()} - {fmt % args}")


if __name__ == "__main__":
    print(f"Audio System timeline API listening on http://{HOST}:{PORT}")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
