"""Smoke test for the persistent Audio System RPS SIP/UDP listener."""

from __future__ import annotations

import json
import socket
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STATE_PATH = ROOT / "runs" / "system-runtime" / "rps-state.json"


def main() -> None:
    deadline = time.monotonic() + 8.0
    state = None
    while time.monotonic() < deadline:
        if STATE_PATH.is_file():
            try:
                candidate = json.loads(STATE_PATH.read_text(encoding="utf-8-sig"))
                if candidate.get("proxy_listener_available"):
                    state = candidate
                    break
            except (OSError, json.JSONDecodeError):
                pass
        time.sleep(0.2)

    if not state:
        raise SystemExit("RPS SIP listener did not become ready")

    bind_ip = str(state.get("bind_ip") or "")
    advertised_ip = str(state.get("advertised_ip") or "127.0.0.1")
    target_ip = "127.0.0.1" if bind_ip == "0.0.0.0" else advertised_ip
    port = int(state["sip_port"])

    call_id = f"rps-smoke-{uuid.uuid4()}@audio-system.local"
    branch = uuid.uuid4().hex
    request = "\r\n".join([
        f"OPTIONS sip:rps@{advertised_ip}:{port} SIP/2.0",
        f"Via: SIP/2.0/UDP 127.0.0.1:0;branch=z9hG4bK-{branch}",
        "From: <sip:smoke@audio-system.local>;tag=smoke",
        f"To: <sip:rps@{advertised_ip}>",
        f"Call-ID: {call_id}",
        "CSeq: 1 OPTIONS",
        "Max-Forwards: 70",
        "Content-Length: 0",
        "",
        "",
    ]).encode("ascii")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(3.0)
    try:
        sock.sendto(request, (target_ip, port))
        payload, _ = sock.recvfrom(8192)
    finally:
        sock.close()

    response = payload.decode("utf-8", errors="replace")
    first = response.split("\r\n", 1)[0]
    if not first.startswith("SIP/2.0 200"):
        raise SystemExit(f"RPS OPTIONS failed: {first}")

    print(
        f"RPS SIP OPTIONS: PASS target={target_ip}:{port} "
        f"advertised={advertised_ip}:{port} mode={state.get('mode')}"
    )


if __name__ == "__main__":
    main()
