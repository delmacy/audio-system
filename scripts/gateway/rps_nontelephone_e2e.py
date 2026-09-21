"""End-to-end RPS media tests for RADIO and CWP paths."""

from __future__ import annotations

import argparse
import json
import random
import re
import socket
import sys
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLAYER_DIR = ROOT / "scripts" / "player"
GATEWAY_DIR = ROOT / "scripts" / "gateway"
for item in (PLAYER_DIR, GATEWAY_DIR):
    if str(item) not in sys.path:
        sys.path.insert(0, str(item))

from config_store import list_cwps, list_services  # noqa: E402
from rps_telephone_e2e import (  # noqa: E402
    RPS_AUDIT,
    RPS_STATE,
    audit_events,
    current_recorder_state,
    pcma_tone_payload,
    recv_until_final,
    rtp_packet,
    sip_user,
    wait_for_recorder_events,
    wait_json,
)


def service_number(label: str) -> str:
    matches = re.findall(r"\d+(?:\.\d+)*", label or "")
    return re.sub(r"\D", "", matches[-1]) if matches else ""


def partial_for_category(recorder: dict, category: str) -> Path:
    files = recorder.get("files") or {}
    item = files.get(category)
    if not isinstance(item, dict) or not item.get("path"):
        raise RuntimeError(f"Current recorder topology has no {category} MXF")
    final_path = Path(str(item["path"])).resolve()
    return Path(str(item.get("partial") or (str(final_path) + ".partial"))).resolve()


def send_dialog(
    *,
    kind: str,
    target_user: str,
    from_user: str,
    extra_headers: list[str],
    expected_direction: str,
    expected_service_id: str,
    category: str,
    display_name: str,
) -> None:
    rps = wait_json(
        RPS_STATE,
        lambda item: bool(item.get("proxy_listener_available")) and item.get("status") == "RUNNING",
        8.0,
        "persistent RPS listener",
    )
    if not rps.get("recorder", {}).get("available"):
        raise RuntimeError("RPS is running, but recorder RTSP is not available")

    _run, recorder = current_recorder_state()
    recorder_audit = Path(str(recorder["audit"])).resolve()
    partial_mxf = partial_for_category(recorder, category)
    size_before = partial_mxf.stat().st_size if partial_mxf.is_file() else 0

    advertised_ip = str(rps.get("advertised_ip") or "127.0.0.1")
    bind_ip = str(rps.get("bind_ip") or "")
    target_ip = "127.0.0.1" if bind_ip == "0.0.0.0" else advertised_ip
    sip_port = int(rps["sip_port"])

    call_id = f"e2e-{kind}-{uuid.uuid4()}@audio-system.local"
    from_tag = uuid.uuid4().hex[:10]
    local_sip = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    local_sip.bind(("127.0.0.1", 0))
    local_sip_port = int(local_sip.getsockname()[1])

    sdp = "\r\n".join([
        "v=0",
        "o=E2E 1 1 IN IP4 127.0.0.1",
        f"s=Audio System {kind.upper()} E2E",
        "c=IN IP4 127.0.0.1",
        "t=0 0",
        "m=audio 9 RTP/AVP 8",
        "a=rtpmap:8 PCMA/8000",
    ]) + "\r\n"

    invite_lines = [
        f"INVITE sip:{target_user}@{advertised_ip}:{sip_port} SIP/2.0",
        f"Via: SIP/2.0/UDP 127.0.0.1:{local_sip_port};branch=z9hG4bK-{uuid.uuid4().hex}",
        f"From: <sip:{from_user}@audio-system.local>;tag={from_tag}",
        f"To: <sip:{target_user}@{advertised_ip}>",
        f"Call-ID: {call_id}",
        "CSeq: 1 INVITE",
        f"Contact: <sip:{from_user}@127.0.0.1:{local_sip_port}>",
        "Max-Forwards: 70",
        *extra_headers,
        "Content-Type: application/sdp",
        f"Content-Length: {len(sdp.encode('ascii'))}",
        "",
        sdp,
    ]
    invite = "\r\n".join(invite_lines).encode("ascii")

    try:
        local_sip.sendto(invite, (target_ip, sip_port))
        _first, response_headers, response_sdp = recv_until_final(local_sip, call_id)
        match = re.search(r"(?im)^m=audio\s+(\d+)\s+RTP/AVP\s+8\b", response_sdp)
        if not match:
            raise RuntimeError(f"SIP 200 OK did not advertise a PCMA RTP port; body={response_sdp!r}")
        rps_rtp_port = int(match.group(1))

        ack = "\r\n".join([
            f"ACK sip:{target_user}@{advertised_ip}:{sip_port} SIP/2.0",
            f"Via: SIP/2.0/UDP 127.0.0.1:{local_sip_port};branch=z9hG4bK-{uuid.uuid4().hex}",
            f"From: <sip:{from_user}@audio-system.local>;tag={from_tag}",
            f"To: {response_headers.get('to', f'<sip:{target_user}@{advertised_ip}>')}",
            f"Call-ID: {call_id}",
            "CSeq: 1 ACK",
            "Content-Length: 0",
            "",
            "",
        ]).encode("ascii")
        local_sip.sendto(ack, (target_ip, sip_port))

        active = wait_json(
            RPS_STATE,
            lambda item: any(session.get("call_id") == call_id for session in item.get("sessions", [])),
            5.0,
            "RPS active recording session",
        )
        session = next(item for item in active["sessions"] if item.get("call_id") == call_id)
        legs = list(session.get("legs") or [])
        if len(legs) != 1:
            raise RuntimeError(f"Expected exactly one {kind} recording leg; got {legs!r}")

        leg = legs[0]
        if leg.get("direction") != expected_direction:
            raise RuntimeError(
                f"Wrong recording direction: expected={expected_direction} actual={leg.get('direction')}"
            )
        if str(leg.get("service_id")) != expected_service_id:
            raise RuntimeError(
                f"Wrong service route: expected={expected_service_id} actual={leg.get('service_id')}"
            )
        route_key = str(leg["route_key"])

        rtp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        packets = 100
        sequence = random.randint(1, 60000)
        timestamp = random.randint(1, 0x7FFFFFFF)
        ssrc = random.randint(1, 0xFFFFFFFF)
        try:
            for packet_index in range(packets):
                payload = pcma_tone_payload(packet_index * 160, frequency_hz=1000.0)
                rtp.sendto(
                    rtp_packet(sequence + packet_index, timestamp + packet_index * 160, ssrc, payload),
                    (target_ip, rps_rtp_port),
                )
                time.sleep(0.020)
        finally:
            rtp.close()

        bye = "\r\n".join([
            f"BYE sip:{target_user}@{advertised_ip}:{sip_port} SIP/2.0",
            f"Via: SIP/2.0/UDP 127.0.0.1:{local_sip_port};branch=z9hG4bK-{uuid.uuid4().hex}",
            f"From: <sip:{from_user}@audio-system.local>;tag={from_tag}",
            f"To: {response_headers.get('to', f'<sip:{target_user}@{advertised_ip}>')}",
            f"Call-ID: {call_id}",
            "CSeq: 2 BYE",
            "Content-Length: 0",
            "",
            "",
        ]).encode("ascii")
        local_sip.sendto(bye, (target_ip, sip_port))
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
            {"RTP_ROUTE_ACTIVE", "MEDIA_START", "MEDIA_END"},
            timeout=8.0,
        )
        kinds = {str(item.get("event")) for item in events}

        rps_events = audit_events(RPS_AUDIT, call_id)
        closed = [item for item in rps_events if item.get("event") == "RPS_RECORDING_CLOSED"]
        if not closed:
            raise RuntimeError(f"RPS close evidence missing for {call_id}")
        close_legs = list(closed[-1].get("legs") or [])
        evidence = next(
            (item for item in close_legs if str(item.get("route_key")) == route_key),
            None,
        )
        if evidence is None:
            raise RuntimeError(f"RPS close evidence missing route {route_key}")

        packets_forwarded = int(evidence.get("packets") or 0)
        bytes_forwarded = int(evidence.get("bytes_forwarded") or 0)
        if packets_forwarded <= 0 or bytes_forwarded <= 0:
            raise RuntimeError(
                f"No real RTP media evidence for {route_key}: "
                f"packets={packets_forwarded} bytes={bytes_forwarded}"
            )

        size_after = partial_mxf.stat().st_size if partial_mxf.is_file() else 0
        if size_after <= size_before:
            raise RuntimeError(
                f"{category} MXF partial did not grow: before={size_before} "
                f"after={size_after} path={partial_mxf}"
            )

        print(f"RPS {kind.upper()} E2E: PASS")
        print(f"  source={display_name} call_id={call_id}")
        print(
            f"  direction={leg.get('direction')} service={leg.get('service_id')} "
            f"track_index={leg.get('track_index')} route={route_key}"
        )
        print(
            f"  packets={packets_forwarded} bytes={bytes_forwarded} "
            f"events={','.join(sorted(kinds))}"
        )
        print(f"  rtp_packets_sent={packets} duration_seconds={packets * 0.020:.2f}")
        print(f"  mxf_partial={partial_mxf}")
        print(f"  mxf_bytes_before={size_before} mxf_bytes_after={size_after}")
    finally:
        local_sip.close()


def run_radio() -> None:
    rps = wait_json(
        RPS_STATE,
        lambda item: bool(item.get("proxy_listener_available")) and item.get("status") == "RUNNING",
        8.0,
        "persistent RPS listener",
    )
    gateway_id = str(rps.get("gateway_id") or "")
    radios = [
        item for item in list_services()
        if item.get("enabled")
        and item.get("kind") == "RADIO"
        and item.get("sip_uri")
        and (not gateway_id or str(item.get("gateway_id") or "") == gateway_id)
    ]
    if not radios:
        raise RuntimeError("No enabled RADIO service is registered on the active RPS")
    radios.sort(key=lambda item: str(item.get("label")))
    service = radios[0]
    user = sip_user(str(service["sip_uri"]))
    number = service_number(str(service["label"]))
    if not user or not number:
        raise RuntimeError(f"Could not derive radio SIP user/frequency from {service!r}")

    send_dialog(
        kind="radio",
        target_user=user,
        from_user="radio-source",
        extra_headers=[],
        expected_direction="radio",
        expected_service_id=number,
        category="radio",
        display_name=str(service["label"]),
    )


def run_cwp() -> None:
    cwps = [item for item in list_cwps() if item.get("enabled")]
    if not cwps:
        raise RuntimeError("No enabled CWP is registered")
    cwps.sort(key=lambda item: (str(item.get("side")), str(item.get("label"))))
    cwp = cwps[0]
    label = str(cwp["label"])

    send_dialog(
        kind="cwp",
        target_user="cwp-recording",
        from_user=label,
        extra_headers=[
            "X-Audio-Category: cwp",
            f"X-Audio-CWP: {label}",
        ],
        expected_direction="cwp",
        expected_service_id=label,
        category="cwp",
        display_name=label,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--kind", choices=("radio", "cwp"), required=True)
    args = parser.parse_args()
    if args.kind == "radio":
        run_radio()
    else:
        run_cwp()


if __name__ == "__main__":
    main()
