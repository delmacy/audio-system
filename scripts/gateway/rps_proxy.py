"""Persistent SIP/UDP to RTSP/RTP recording proxy for the Audio System PoC.

This is deliberately a bounded SIP ingress, not a general-purpose SIP proxy,
registrar, B2BUA, NAT traversal stack, or ED-137 implementation.
"""

from __future__ import annotations

import argparse
import json
import re
import socket
import sys
import threading
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[2]
PLAYER_DIR = ROOT / "scripts" / "player"
if str(PLAYER_DIR) not in sys.path:
    sys.path.insert(0, str(PLAYER_DIR))

from config_store import list_cwps, list_gateways, list_services  # noqa: E402

RUNTIME_DIR = ROOT / "runs" / "system-runtime"
STATE_PATH = RUNTIME_DIR / "rps-state.json"
AUDIT_PATH = RUNTIME_DIR / "rps-audit.jsonl"
RECORDER_RUNS = ROOT / "runs" / "operational-recorder"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def audit(event: str, **fields: object) -> None:
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    payload = {"ts_utc": utc_now(), "event": event, **fields}
    with AUDIT_PATH.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")


def atomic_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    temp.replace(path)


def sip_user(uri: str) -> str:
    match = re.search(r"sips?:([^@;>\s]+)", uri or "", re.IGNORECASE)
    return match.group(1) if match else ""


def service_number(label: str) -> str:
    matches = re.findall(r"\d+(?:\.\d+)*", label or "")
    return re.sub(r"\D", "", matches[-1]) if matches else ""


def local_ipv4_addresses() -> set[str]:
    result = {"0.0.0.0", "127.0.0.1"}
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            result.add(info[4][0])
    except OSError:
        pass
    return result


@dataclass
class SipMessage:
    start_line: str
    headers: dict[str, str]
    body: str
    method: str = ""
    request_uri: str = ""

    @classmethod
    def parse(cls, payload: bytes) -> "SipMessage":
        text = payload.decode("utf-8", errors="replace")
        head, _, body = text.partition("\r\n\r\n")
        if not body and "\n\n" in text:
            head, _, body = text.partition("\n\n")
        lines = head.replace("\r\n", "\n").split("\n")
        start = lines[0].strip() if lines else ""
        headers: dict[str, str] = {}
        current = ""
        for raw in lines[1:]:
            if raw.startswith((" ", "\t")) and current:
                headers[current] += " " + raw.strip()
                continue
            if ":" not in raw:
                continue
            key, value = raw.split(":", 1)
            current = key.strip().lower()
            headers[current] = value.strip()
        parts = start.split()
        method = parts[0].upper() if parts and not start.upper().startswith("SIP/") else ""
        request_uri = parts[1] if len(parts) > 1 and method else ""
        return cls(start, headers, body, method, request_uri)

    def header(self, name: str, default: str = "") -> str:
        return self.headers.get(name.lower(), default)


class RtspClient:
    def __init__(self, host: str, port: int, local_ip: str) -> None:
        self.host = host
        self.port = port
        self.local_ip = local_ip
        self.sock: socket.socket | None = None
        self.cseq = 0
        self.session = ""

    def connect(self) -> None:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(4.0)
        bind_ip = self.local_ip if self.local_ip in local_ipv4_addresses() else "0.0.0.0"
        sock.bind((bind_ip, 0))
        sock.connect((self.host, self.port))
        self.sock = sock

    def request(self, method: str, uri: str, body: str = "", headers: dict[str, str] | None = None) -> str:
        if not self.sock:
            raise RuntimeError("RTSP socket is not connected")
        self.cseq += 1
        lines = [
            f"{method} {uri} RTSP/1.0",
            f"CSeq: {self.cseq}",
            "User-Agent: audio-system-rps/1.0",
        ]
        if self.session and method not in {"OPTIONS", "ANNOUNCE"}:
            lines.append(f"Session: {self.session}")
        for key, value in (headers or {}).items():
            lines.append(f"{key}: {value}")
        body_bytes = body.encode("ascii", errors="replace")
        if body:
            if not any(key.lower() == "content-type" for key in (headers or {})):
                lines.append("Content-Type: application/sdp")
            lines.append(f"Content-Length: {len(body_bytes)}")
        else:
            lines.append("Content-Length: 0")
        raw = ("\r\n".join(lines) + "\r\n\r\n").encode("ascii") + body_bytes
        self.sock.sendall(raw)

        received = b""
        while b"\r\n\r\n" not in received:
            chunk = self.sock.recv(8192)
            if not chunk:
                raise RuntimeError(f"RTSP socket closed during {method}")
            received += chunk
        response = received.decode("utf-8", errors="replace")
        first = response.split("\r\n", 1)[0]
        if not re.match(r"RTSP/1\.0\s+200\b", first):
            raise RuntimeError(f"{method} failed: {first}")
        match = re.search(r"(?im)^Session:\s*([^;\r\n]+)", response)
        if match:
            self.session = match.group(1).strip()
        return response

    def close(self) -> None:
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass
            self.sock = None


@dataclass
class ActiveSession:
    call_id: str
    peer: tuple[str, int]
    service_id: str
    service_kind: str
    route_key: str
    track_index: int
    recorder_rtp_port: int
    local_rtp_port: int
    direction: str
    cwp_id: str | None
    slot_index: int | None
    sip_from_raw: str
    sip_to_raw: str
    sip_from_user: str
    sip_to_user: str
    remote_party_user: str
    rtsp: RtspClient
    rtp_socket: socket.socket
    relay_stop: threading.Event
    relay_thread: threading.Thread
    started_utc: str = field(default_factory=utc_now)
    packets: int = 0
    bytes_forwarded: int = 0


class RpsProxy:
    def __init__(self, gateway_id: str | None = None) -> None:
        gateways = [item for item in list_gateways() if item.get("enabled")]
        if gateway_id:
            gateways = [item for item in gateways if item["id"] == gateway_id]
        if not gateways:
            raise RuntimeError("No enabled RPS is configured")
        if len(gateways) > 1 and not gateway_id:
            gateways.sort(key=lambda item: (str(item["label"]), str(item["id"])))
        self.gateway = gateways[0]
        self.advertised_ip = str(self.gateway["ip"])
        self.sip_port = int(self.gateway["sip_port"])
        self.gateway_id = str(self.gateway["id"])
        self.gateway_label = str(self.gateway["label"])
        parsed = urlparse(str(self.gateway["rtsp_base_url"]))
        if parsed.scheme.lower() != "rtsp" or not parsed.hostname:
            raise RuntimeError("Configured RPS RTSP destination is invalid")
        self.recorder_ip = parsed.hostname
        self.recorder_rtsp_port = parsed.port or 554

        self.bind_ip = self.advertised_ip if self.advertised_ip in local_ipv4_addresses() else "0.0.0.0"
        self.sip_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sip_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sip_socket.bind((self.bind_ip, self.sip_port))
        self.sip_socket.settimeout(0.5)

        self.sessions: dict[str, ActiveSession] = {}
        self.lock = threading.RLock()
        self.started_utc = utc_now()
        self.last_request_utc: str | None = None
        self.last_error: str | None = None
        self.shutdown = threading.Event()

    def current_topology(self) -> tuple[dict, Path]:
        pointer = RECORDER_RUNS / "current-run.txt"
        if not pointer.is_file():
            raise RuntimeError("Recorder has no current run")
        run = Path(pointer.read_text(encoding="utf-8-sig").strip()).resolve()
        state_path = run / "operational-recorder-state.json"
        if not state_path.is_file():
            raise RuntimeError("Recorder state is unavailable")
        state = json.loads(state_path.read_text(encoding="utf-8-sig"))
        pid = int(state.get("pid") or 0)
        if not pid:
            raise RuntimeError("Recorder state has no active PID")
        manifest_path = Path(str(state.get("topology_manifest") or "")).resolve()
        if not manifest_path.is_file():
            raise RuntimeError("Recorder topology manifest is unavailable")
        return json.loads(manifest_path.read_text(encoding="utf-8-sig")), run

    def service_by_user(self, user: str) -> dict | None:
        normalized = re.sub(r"\D", "", user)
        for service in list_services():
            if not service.get("enabled") or service.get("gateway_id") != self.gateway_id:
                continue
            uri_user = sip_user(str(service.get("sip_uri") or ""))
            if user == uri_user or (normalized and normalized == service_number(str(service.get("label") or ""))):
                return service
        return None

    def resolve_cwp(self, message: SipMessage, peer_ip: str) -> dict | None:
        requested = message.header("x-audio-cwp").strip()
        cwps = [item for item in list_cwps() if item.get("enabled")]
        if requested:
            lowered = requested.lower()
            for cwp in cwps:
                if str(cwp["id"]).lower() == lowered or str(cwp["label"]).lower() == lowered:
                    return cwp
            return None
        matches = [item for item in cwps if str(item.get("ip")) == peer_ip]
        if len(matches) == 1:
            return matches[0]
        if len(cwps) == 1:
            return cwps[0]
        return None

    def telephone_slot(self, number: str, direction: str, tracks: list[dict]) -> dict | None:
        candidates = [
            track for track in tracks
            if track.get("category") == "telephone"
            and str(track.get("service_id")) == number
            and track.get("role") == direction
        ]
        with self.lock:
            used = {
                session.slot_index
                for session in self.sessions.values()
                if session.service_id == number and session.direction == direction
            }
        for track in sorted(candidates, key=lambda item: int(item.get("slot_index") or 0)):
            if int(track.get("slot_index") or 0) not in used:
                return track
        return None

    def telephone_service_and_direction(self, message: SipMessage) -> tuple[dict, str, str, str]:
        request_user = sip_user(message.request_uri)
        to_user = sip_user(message.header("to")) or request_user
        from_user = sip_user(message.header("from"))

        to_service = self.service_by_user(to_user) if to_user else None
        from_service = self.service_by_user(from_user) if from_user else None
        if to_service and to_service.get("kind") == "TEL":
            return to_service, "received", from_user, to_user
        if from_service and from_service.get("kind") == "TEL":
            return from_service, "calling", from_user, to_user

        raise LookupError(
            f"No enabled telephone service matches SIP From='{from_user}' or To='{to_user}'"
        )

    def resolve_track(self, message: SipMessage, peer_ip: str) -> tuple[dict, dict | None, str, dict]:
        topology, _ = self.current_topology()
        tracks = list(topology.get("tracks") or [])
        category = message.header("x-audio-category").strip().lower()
        request_user = sip_user(message.request_uri)

        if category == "cwp":
            cwp = self.resolve_cwp(message, peer_ip)
            if not cwp:
                raise ValueError("CWP route requires X-Audio-CWP or an unambiguous CWP source IP")
            route = f"/record/{cwp['label']}/cwp-rx"
            track = next((item for item in tracks if item.get("route_key") == route), None)
            if not track:
                raise LookupError(f"CWP track is not present in current recorder topology: {route}")
            return track, cwp, "cwp", {
                "from_user": sip_user(message.header("from")),
                "to_user": sip_user(message.header("to")) or request_user,
                "remote_party_user": "",
            }

        service = self.service_by_user(request_user)
        if service and service["kind"] == "RADIO":
            number = service_number(str(service["label"]))
            route = f"/record/radio/{number}"
            track = next((item for item in tracks if item.get("route_key") == route), None)
            if not track:
                raise LookupError(f"Radio track is not present in current recorder topology: {route}")
            return track, None, "radio", {
                "from_user": sip_user(message.header("from")),
                "to_user": sip_user(message.header("to")) or request_user,
                "remote_party_user": "",
            }

        service, inferred_direction, from_user, to_user = self.telephone_service_and_direction(message)
        explicit_direction = message.header("x-audio-direction").strip().lower()
        direction = explicit_direction or inferred_direction
        if direction not in {"received", "calling"}:
            raise ValueError("Telephone direction must be received or calling")

        number = service_number(str(service["label"]))
        track = self.telephone_slot(number, direction, tracks)
        if not track:
            raise RuntimeError(f"No free {direction} slot is available for telephone {number}")

        recorded_user = sip_user(str(service.get("sip_uri") or "")) or number
        remote_party = from_user if direction == "received" else to_user
        metadata = {
            "from_user": from_user,
            "to_user": to_user,
            "recorded_user": recorded_user,
            "remote_party_user": remote_party,
        }
        return track, self.resolve_cwp(message, peer_ip), direction, metadata

    def sip_response(
        self,
        request: SipMessage,
        peer: tuple[str, int],
        code: int,
        reason: str,
        body: str = "",
        extra_headers: dict[str, str] | None = None,
    ) -> None:
        to_value = request.header("to")
        if code >= 180 and "tag=" not in to_value.lower():
            to_value = to_value + f";tag=rps-{self.gateway_id[:8]}"
        headers = [
            f"SIP/2.0 {code} {reason}",
            f"Via: {request.header('via')}",
            f"From: {request.header('from')}",
            f"To: {to_value}",
            f"Call-ID: {request.header('call-id')}",
            f"CSeq: {request.header('cseq')}",
            f"Server: audio-system-rps/1.0",
        ]
        for key, value in (extra_headers or {}).items():
            headers.append(f"{key}: {value}")
        body_bytes = body.encode("ascii", errors="replace")
        if body:
            headers.append("Content-Type: application/sdp")
        headers.append(f"Content-Length: {len(body_bytes)}")
        payload = ("\r\n".join(headers) + "\r\n\r\n").encode("ascii") + body_bytes
        self.sip_socket.sendto(payload, peer)

    def _relay_loop(
        self,
        call_id: str,
        udp: socket.socket,
        target: tuple[str, int],
        stop: threading.Event,
    ) -> None:
        udp.settimeout(0.5)
        while not stop.is_set():
            try:
                packet, _source = udp.recvfrom(65535)
            except socket.timeout:
                continue
            except OSError:
                break
            if not packet:
                continue
            try:
                udp.sendto(packet, target)
                with self.lock:
                    session = self.sessions.get(call_id)
                    if session:
                        session.packets += 1
                        session.bytes_forwarded += len(packet)
            except OSError as exc:
                self.last_error = str(exc)
                audit("RPS_RTP_FORWARD_ERROR", call_id=call_id, error=str(exc))
                break

    def open_recording(self, request: SipMessage, peer: tuple[str, int]) -> ActiveSession:
        call_id = request.header("call-id").strip()
        if not call_id:
            raise ValueError("SIP INVITE requires Call-ID")
        with self.lock:
            if call_id in self.sessions:
                return self.sessions[call_id]

        track, cwp, direction, sip_meta = self.resolve_track(request, peer[0])
        route = str(track["route_key"])
        recorder_rtp_port = int(track["rtp_port"])
        number = str(track["service_id"])

        udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        udp_bind_ip = self.bind_ip
        udp.bind((udp_bind_ip, 0))
        local_rtp_port = int(udp.getsockname()[1])

        rtsp = RtspClient(self.recorder_ip, self.recorder_rtsp_port, self.bind_ip)
        rtsp.connect()
        uri = f"rtsp://{self.recorder_ip}:{self.recorder_rtsp_port}{route}"
        rtsp.request("OPTIONS", uri)
        sdp = "\r\n".join([
            "v=0",
            f"o=RPS 1 1 IN IP4 {self.advertised_ip}",
            f"s=Audio System RPS {number}",
            f"c=IN IP4 {self.advertised_ip}",
            "t=0 0",
            f"m=audio {local_rtp_port} RTP/AVP 8",
            "a=rtpmap:8 PCMA/8000",
            f"a=label:{track.get('display_name') or route}",
            "a=mid:audio0",
            f"a=x-sip-call-id:{call_id}",
        ]) + "\r\n"
        rtsp.request("ANNOUNCE", uri, sdp, {"Content-Type": "application/sdp"})
        rtsp.request(
            "SETUP",
            uri,
            headers={"Transport": f"RTP/AVP;unicast;client_port={local_rtp_port}-{local_rtp_port + 1};mode=record"},
        )
        rtsp.request("RECORD", uri)

        stop = threading.Event()
        thread = threading.Thread(
            target=self._relay_loop,
            args=(call_id, udp, (self.recorder_ip, recorder_rtp_port), stop),
            name=f"rps-rtp-{call_id[:12]}",
            daemon=True,
        )
        service_kind = "CWP" if direction == "cwp" else ("RADIO" if track.get("category") == "radio" else "TEL")
        session = ActiveSession(
            call_id=call_id,
            peer=peer,
            service_id=number,
            service_kind=service_kind,
            route_key=route,
            track_index=int(track["track_index"]),
            recorder_rtp_port=recorder_rtp_port,
            local_rtp_port=local_rtp_port,
            direction=direction,
            cwp_id=str(cwp["id"]) if cwp else None,
            slot_index=int(track["slot_index"]) if track.get("slot_index") is not None else None,
            sip_from_raw=request.header("from"),
            sip_to_raw=request.header("to"),
            sip_from_user=str(sip_meta.get("from_user") or ""),
            sip_to_user=str(sip_meta.get("to_user") or ""),
            remote_party_user=str(sip_meta.get("remote_party_user") or ""),
            rtsp=rtsp,
            rtp_socket=udp,
            relay_stop=stop,
            relay_thread=thread,
        )
        with self.lock:
            self.sessions[call_id] = session
        thread.start()
        audit(
            "RPS_RECORDING_OPEN",
            call_id=call_id,
            route_key=route,
            track_index=session.track_index,
            recorder_rtp_port=recorder_rtp_port,
            local_rtp_port=local_rtp_port,
            direction=direction,
            cwp_id=session.cwp_id,
            slot_index=session.slot_index,
            sip_from_raw=session.sip_from_raw,
            sip_to_raw=session.sip_to_raw,
            sip_from_user=session.sip_from_user,
            sip_to_user=session.sip_to_user,
            remote_party_user=session.remote_party_user,
        )
        return session

    def close_recording(self, call_id: str, reason: str) -> None:
        with self.lock:
            session = self.sessions.pop(call_id, None)
        if not session:
            return
        session.relay_stop.set()
        try:
            session.rtsp.request("PAUSE", f"rtsp://{self.recorder_ip}:{self.recorder_rtsp_port}{session.route_key}")
        except Exception as exc:
            audit("RPS_RTSP_PAUSE_FAILED", call_id=call_id, error=str(exc))
        try:
            session.rtsp.request("TEARDOWN", f"rtsp://{self.recorder_ip}:{self.recorder_rtsp_port}{session.route_key}")
        except Exception as exc:
            audit("RPS_RTSP_TEARDOWN_FAILED", call_id=call_id, error=str(exc))
        try:
            session.rtp_socket.close()
        except OSError:
            pass
        session.rtsp.close()
        session.relay_thread.join(timeout=1.0)
        audit(
            "RPS_RECORDING_CLOSED",
            call_id=call_id,
            reason=reason,
            packets=session.packets,
            bytes=session.bytes_forwarded,
            route_key=session.route_key,
        )

    def status(self) -> dict:
        recorder_available = False
        try:
            with socket.create_connection((self.recorder_ip, self.recorder_rtsp_port), timeout=0.15):
                recorder_available = True
        except OSError:
            pass
        with self.lock:
            sessions = list(self.sessions.values())
        return {
            "schema": "audio-system.rps-runtime.v2",
            "checked_utc": utc_now(),
            "started_utc": self.started_utc,
            "status": "RUNNING",
            "mode": "persistent_sip_udp_to_rtsp",
            "gateway_id": self.gateway_id,
            "gateway_label": self.gateway_label,
            "bind_ip": self.bind_ip,
            "advertised_ip": self.advertised_ip,
            "sip_port": self.sip_port,
            "transport": "udp",
            "proxy_listener_available": True,
            "recorder": {
                "ip": self.recorder_ip,
                "rtsp_port": self.recorder_rtsp_port,
                "available": recorder_available,
            },
            "active_sessions": len(sessions),
            "sessions": [
                {
                    "call_id": item.call_id,
                    "service_id": item.service_id,
                    "service_kind": item.service_kind,
                    "direction": item.direction,
                    "route_key": item.route_key,
                    "track_index": item.track_index,
                    "slot_index": item.slot_index,
                    "cwp_id": item.cwp_id,
                    "sip_from_user": item.sip_from_user,
                    "sip_to_user": item.sip_to_user,
                    "remote_party_user": item.remote_party_user,
                    "local_rtp_port": item.local_rtp_port,
                    "recorder_rtp_port": item.recorder_rtp_port,
                    "packets": item.packets,
                    "bytes_forwarded": item.bytes_forwarded,
                    "started_utc": item.started_utc,
                }
                for item in sessions
            ],
            "last_request_utc": self.last_request_utc,
            "last_error": self.last_error,
            "note": "Bounded SIP/UDP recording ingress; not a registrar, NAT traversal stack, or full SIP proxy.",
        }

    def handle(self, payload: bytes, peer: tuple[str, int]) -> None:
        message = SipMessage.parse(payload)
        self.last_request_utc = utc_now()
        method = message.method
        audit("RPS_SIP_REQUEST", method=method, peer=f"{peer[0]}:{peer[1]}", call_id=message.header("call-id"))

        if method == "OPTIONS":
            self.sip_response(message, peer, 200, "OK", extra_headers={"Allow": "OPTIONS, INVITE, ACK, BYE, CANCEL"})
            return
        if method == "ACK":
            return
        if method in {"BYE", "CANCEL"}:
            self.close_recording(message.header("call-id"), method)
            self.sip_response(message, peer, 200, "OK")
            return
        if method != "INVITE":
            self.sip_response(message, peer, 405, "Method Not Allowed", extra_headers={"Allow": "OPTIONS, INVITE, ACK, BYE, CANCEL"})
            return

        self.sip_response(message, peer, 100, "Trying")
        try:
            session = self.open_recording(message, peer)
            self.sip_response(message, peer, 180, "Ringing")
            sdp = "\r\n".join([
                "v=0",
                f"o=RPS 1 1 IN IP4 {self.advertised_ip}",
                "s=Audio System RPS",
                f"c=IN IP4 {self.advertised_ip}",
                "t=0 0",
                f"m=audio {session.local_rtp_port} RTP/AVP 8",
                "a=rtpmap:8 PCMA/8000",
                "a=sendrecv",
            ]) + "\r\n"
            self.sip_response(
                message,
                peer,
                200,
                "OK",
                sdp,
                {"Contact": f"<sip:rps@{self.advertised_ip}:{self.sip_port}>"},
            )
        except LookupError as exc:
            self.last_error = str(exc)
            audit("RPS_ROUTE_NOT_FOUND", call_id=message.header("call-id"), error=str(exc))
            self.sip_response(message, peer, 404, "Not Found")
        except ValueError as exc:
            self.last_error = str(exc)
            audit("RPS_BAD_REQUEST", call_id=message.header("call-id"), error=str(exc))
            self.sip_response(message, peer, 400, "Bad Request")
        except (ConnectionError, OSError, RuntimeError) as exc:
            self.last_error = str(exc)
            audit("RPS_RECORDER_UNAVAILABLE", call_id=message.header("call-id"), error=str(exc))
            self.sip_response(message, peer, 503, "Service Unavailable")

    def run(self) -> None:
        audit(
            "RPS_STARTED",
            gateway_id=self.gateway_id,
            bind_ip=self.bind_ip,
            advertised_ip=self.advertised_ip,
            sip_port=self.sip_port,
            recorder=f"{self.recorder_ip}:{self.recorder_rtsp_port}",
        )
        last_state = 0.0
        try:
            while not self.shutdown.is_set():
                now = time.monotonic()
                if now - last_state >= 1.0:
                    atomic_json(STATE_PATH, self.status())
                    last_state = now
                try:
                    payload, peer = self.sip_socket.recvfrom(65535)
                except socket.timeout:
                    continue
                except OSError:
                    break
                if payload:
                    self.handle(payload, peer)
        finally:
            with self.lock:
                call_ids = list(self.sessions)
            for call_id in call_ids:
                self.close_recording(call_id, "RPS_SHUTDOWN")
            try:
                self.sip_socket.close()
            except OSError:
                pass
            stopped = self.status()
            stopped["status"] = "STOPPED"
            stopped["proxy_listener_available"] = False
            atomic_json(STATE_PATH, stopped)
            audit("RPS_STOPPED")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--gateway-id")
    args = parser.parse_args()
    proxy = RpsProxy(args.gateway_id)
    try:
        proxy.run()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
