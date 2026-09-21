"""End-to-end telephone recording smoke: SIP -> RPS -> RTSP/RTP -> recorder -> MXF."""

from __future__ import annotations

import json
import math
import random
import re
import socket
import struct
import sys
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLAYER_DIR = ROOT / "scripts" / "player"
if str(PLAYER_DIR) not in sys.path:
    sys.path.insert(0, str(PLAYER_DIR))

from config_store import list_services  # noqa: E402

RPS_STATE = ROOT / "runs" / "system-runtime" / "rps-state.json"
RPS_AUDIT = ROOT / "runs" / "system-runtime" / "rps-audit.jsonl"
RECORDER_RUNS = ROOT / "runs" / "operational-recorder"


def sip_user(uri: str) -> str:
    match = re.search(r"sips?:([^@;>\s]+)", uri or "", re.IGNORECASE)
    return match.group(1) if match else ""


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def wait_json(path: Path, predicate, timeout: float, description: str) -> dict:
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            if path.is_file():
                last = read_json(path)
                if predicate(last):
                    return last
        except (OSError, json.JSONDecodeError):
            pass
        time.sleep(0.15)
    raise RuntimeError(f"Timed out waiting for {description}; last={last!r}")


def current_recorder_state() -> tuple[Path, dict]:
    pointer = RECORDER_RUNS / "current-run.txt"
    if not pointer.is_file():
        raise RuntimeError("Recorder current-run.txt is missing; start the system first")
    run = Path(pointer.read_text(encoding="utf-8-sig").strip()).resolve()
    state_path = run / "operational-recorder-state.json"
    if not state_path.is_file():
        raise RuntimeError(f"Recorder state is missing: {state_path}")
    state = read_json(state_path)
    return run, state


def parse_sip_message(payload: bytes) -> tuple[str, dict[str, str], str]:
    text = payload.decode("utf-8", errors="replace")
    head, _, body = text.partition("\r\n\r\n")
    lines = head.split("\r\n")
    first = lines[0] if lines else ""
    headers: dict[str, str] = {}
    for line in lines[1:]:
        if ":" in line:
            key, value = line.split(":", 1)
            headers[key.strip().lower()] = value.strip()
    return first, headers, body


def recv_until_final(sock: socket.socket, call_id: str, timeout: float = 6.0) -> tuple[str, dict[str, str], str]:
    deadline = time.monotonic() + timeout
    seen = []
    while time.monotonic() < deadline:
        sock.settimeout(max(0.1, deadline - time.monotonic()))
        try:
            payload, _ = sock.recvfrom(65535)
        except socket.timeout:
            break
        first, headers, body = parse_sip_message(payload)
        if headers.get("call-id") != call_id:
            continue
        seen.append(first)
        match = re.match(r"SIP/2\.0\s+(\d+)", first)
        if not match:
            continue
        code = int(match.group(1))
        if code >= 200:
            if code != 200:
                raise RuntimeError(f"SIP INVITE failed: {first}; provisional={seen[:-1]}")
            return first, headers, body
    raise RuntimeError(f"No final SIP response for Call-ID {call_id}; seen={seen}")


def alaw_encode(sample: int) -> int:
    # ITU-T G.711 A-law, 16-bit signed PCM -> 8-bit A-law.
    sample = max(-32768, min(32767, sample))
    sign = 0x80 if sample >= 0 else 0x00
    if sample < 0:
        sample = -sample - 1
    sample >>= 3

    if sample < 16:
        exponent = 0
        mantissa = sample
    else:
        exponent = min(7, sample.bit_length() - 5)
        mantissa = (sample >> exponent) & 0x0F

    value = sign | (exponent << 4) | mantissa
    return value ^ 0x55


def pcma_tone_payload(
    sample_offset: int,
    samples: int = 160,
    frequency_hz: float = 880.0,
    sample_rate: int = 8000,
    amplitude: int = 9000,
) -> bytes:
    payload = bytearray(samples)
    for index in range(samples):
        position = sample_offset + index
        pcm = int(amplitude * math.sin(2.0 * math.pi * frequency_hz * position / sample_rate))
        payload[index] = alaw_encode(pcm)
    return bytes(payload)


def rtp_packet(sequence: int, timestamp: int, ssrc: int, payload: bytes) -> bytes:
    return struct.pack(
        "!BBHII",
        0x80,
        8,
        sequence & 0xFFFF,
        timestamp & 0xFFFFFFFF,
        ssrc & 0xFFFFFFFF,
    ) + payload


def audit_events(path: Path, call_id: str | None = None) -> list[dict]:
    if not path.is_file():
        return []
    result = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.strip():
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue
        if call_id is None or item.get("call_id") == call_id:
            result.append(item)
    return result


def recorder_events(path: Path, route_key: str) -> list[dict]:
    if not path.is_file():
        return []
    result = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.strip():
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue
        if item.get("route_key") == route_key:
            result.append(item)
    return result


def wait_for_recorder_events(path: Path, route_key: str, required: set[str], timeout: float = 8.0) -> list[dict]:
    deadline = time.monotonic() + timeout
    last: list[dict] = []
    while time.monotonic() < deadline:
        last = recorder_events(path, route_key)
        kinds = {str(item.get("event")) for item in last}
        if required.issubset(kinds):
            return last
        time.sleep(0.2)
    raise RuntimeError(
        f"Recorder audit did not contain {sorted(required)} for route {route_key}; "
        f"seen={sorted({str(item.get('event')) for item in last})}"
    )


def main() -> None:
    rps = wait_json(
        RPS_STATE,
        lambda item: bool(item.get("proxy_listener_available")) and item.get("status") == "RUNNING",
        8.0,
        "persistent RPS listener",
    )
    if not rps.get("recorder", {}).get("available"):
        raise RuntimeError("RPS is running, but recorder RTSP is not available")

    services = [
        item for item in list_services()
        if item.get("enabled") and item.get("kind") == "TEL" and item.get("sip_uri")
    ]
    if not services:
        raise RuntimeError("No enabled TEL service with SIP URI is registered")
    services.sort(key=lambda item: str(item.get("label")))
    service = services[0]
    recorded_user = sip_user(str(service["sip_uri"]))
    if not recorded_user:
        raise RuntimeError(f"Could not derive SIP user from {service['sip_uri']!r}")

    run, recorder = current_recorder_state()
    recorder_audit = Path(str(recorder["audit"])).resolve()
    files = recorder.get("files") or {}
    telephone = files.get("telephone")
    if not isinstance(telephone, dict) or not telephone.get("path"):
        raise RuntimeError("Current recorder topology has no telephone MXF")
    final_mxf = Path(str(telephone["path"])).resolve()
    partial_mxf = Path(str(telephone.get("partial") or (str(final_mxf) + ".partial"))).resolve()
    size_before = partial_mxf.stat().st_size if partial_mxf.is_file() else 0

    advertised_ip = str(rps.get("advertised_ip") or "127.0.0.1")
    bind_ip = str(rps.get("bind_ip") or "")
    target_ip = "127.0.0.1" if bind_ip == "0.0.0.0" else advertised_ip
    sip_port = int(rps["sip_port"])

    call_id = f"e2e-{uuid.uuid4()}@audio-system.local"
    branch = "z9hG4bK-" + uuid.uuid4().hex
    from_tag = uuid.uuid4().hex[:10]
    remote_user = "9901"
    local_sip = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    local_sip.bind(("127.0.0.1", 0))
    local_sip_port = int(local_sip.getsockname()[1])

    invite_sdp = "\r\n".join([
        "v=0",
        f"o=E2E 1 1 IN IP4 127.0.0.1",
        "s=Audio System E2E",
        "c=IN IP4 127.0.0.1",
        "t=0 0",
        "m=audio 9 RTP/AVP 8",
        "a=rtpmap:8 PCMA/8000",
    ]) + "\r\n"
    invite = "\r\n".join([
        f"INVITE sip:{recorded_user}@{advertised_ip}:{sip_port} SIP/2.0",
        f"Via: SIP/2.0/UDP 127.0.0.1:{local_sip_port};branch={branch}",
        f"From: <sip:{remote_user}@audio-system.local>;tag={from_tag}",
        f"To: <sip:{recorded_user}@{advertised_ip}>",
        f"Call-ID: {call_id}",
        "CSeq: 1 INVITE",
        f"Contact: <sip:{remote_user}@127.0.0.1:{local_sip_port}>",
        "Max-Forwards: 70",
        "Content-Type: application/sdp",
        f"Content-Length: {len(invite_sdp.encode('ascii'))}",
        "",
        invite_sdp,
    ]).encode("ascii")

    try:
        local_sip.sendto(invite, (target_ip, sip_port))
        first, response_headers, response_sdp = recv_until_final(local_sip, call_id)
        match = re.search(r"(?im)^m=audio\s+(\d+)\s+RTP/AVP\s+8\b", response_sdp)
        if not match:
            raise RuntimeError(f"SIP 200 OK did not advertise a PCMA RTP port; body={response_sdp!r}")
        rps_rtp_port = int(match.group(1))

        ack = "\r\n".join([
            f"ACK sip:{recorded_user}@{advertised_ip}:{sip_port} SIP/2.0",
            f"Via: SIP/2.0/UDP 127.0.0.1:{local_sip_port};branch=z9hG4bK-{uuid.uuid4().hex}",
            f"From: <sip:{remote_user}@audio-system.local>;tag={from_tag}",
            f"To: {response_headers.get('to', f'<sip:{recorded_user}@{advertised_ip}>')}",
            f"Call-ID: {call_id}",
            "CSeq: 1 ACK",
            "Content-Length: 0",
            "",
            "",
        ]).encode("ascii")
        local_sip.sendto(ack, (target_ip, sip_port))

        # Wait until the RPS publishes which track/slot it selected.
        active = wait_json(
            RPS_STATE,
            lambda item: any(session.get("call_id") == call_id for session in item.get("sessions", [])),
            5.0,
            "RPS active recording session",
        )
        session = next(session for session in active["sessions"] if session.get("call_id") == call_id)
        route_key = str(session["route_key"])
        track_index = int(session["track_index"])
        slot_index = int(session["slot_index"])

        rtp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sequence = random.randint(1, 60000)
        timestamp = random.randint(1, 0x7FFFFFFF)
        ssrc = random.randint(1, 0xFFFFFFFF)
        packets = 100  # 2 seconds at 20 ms / 160 samples.
        try:
            for packet_index in range(packets):
                payload = pcma_tone_payload(packet_index * 160)
                rtp.sendto(
                    rtp_packet(sequence + packet_index, timestamp + packet_index * 160, ssrc, payload),
                    (target_ip, rps_rtp_port),
                )
                time.sleep(0.020)
        finally:
            rtp.close()

        bye = "\r\n".join([
            f"BYE sip:{recorded_user}@{advertised_ip}:{sip_port} SIP/2.0",
            f"Via: SIP/2.0/UDP 127.0.0.1:{local_sip_port};branch=z9hG4bK-{uuid.uuid4().hex}",
            f"From: <sip:{remote_user}@audio-system.local>;tag={from_tag}",
            f"To: {response_headers.get('to', f'<sip:{recorded_user}@{advertised_ip}>')}",
            f"Call-ID: {call_id}",
            "CSeq: 2 BYE",
            "Content-Length: 0",
            "",
            "",
        ]).encode("ascii")
        local_sip.sendto(bye, (target_ip, sip_port))

        # BYE receives 200 and the session must disappear from RPS state.
        recv_until_final(local_sip, call_id, timeout=4.0)
        wait_json(
            RPS_STATE,
            lambda item: not any(session.get("call_id") == call_id for session in item.get("sessions", [])),
            5.0,
            "RPS session close",
        )

        events = wait_for_recorder_events(
            recorder_audit,
            route_key,
            {"MEDIA_START", "MEDIA_END"},
            timeout=8.0,
        )
        size_after = partial_mxf.stat().st_size if partial_mxf.is_file() else 0
        if size_after <= size_before:
            raise RuntimeError(
                f"Telephone MXF partial did not grow: before={size_before} after={size_after} path={partial_mxf}"
            )

        rps_events = audit_events(RPS_AUDIT, call_id)
        rps_kinds = {str(item.get("event")) for item in rps_events}
        if not {"RPS_RECORDING_OPEN", "RPS_RECORDING_CLOSED"}.issubset(rps_kinds):
            raise RuntimeError(f"RPS audit incomplete for {call_id}: {sorted(rps_kinds)}")

        recorder_kinds = {str(item.get("event")) for item in events}
        print("RPS TELEPHONE E2E: PASS")
        print(f"  service={service['label']} sip_user={recorded_user} remote_party={remote_user}")
        print(f"  direction=received slot={slot_index} track_index={track_index}")
        print(f"  route={route_key}")
        print(f"  rtp_packets_sent={packets} duration_seconds={packets * 0.020:.2f}")
        print(f"  mxf_partial={partial_mxf}")
        print(f"  mxf_bytes_before={size_before} mxf_bytes_after={size_after}")
        print(f"  recorder_events={','.join(sorted(recorder_kinds))}")
        print(f"  call_id={call_id}")
    finally:
        local_sip.close()


if __name__ == "__main__":
    main()
