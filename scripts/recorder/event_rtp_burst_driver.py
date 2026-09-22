from __future__ import annotations

import argparse
import json
import socket
import struct
import time
import uuid
from pathlib import Path


def recv_rtsp(sock: socket.socket) -> str:
    data = bytearray()
    sock.settimeout(10.0)
    while b"\r\n\r\n" not in data:
        chunk = sock.recv(8192)
        if not chunk:
            raise RuntimeError("RTSP peer closed connection")
        data.extend(chunk)
    return data.decode("ascii", errors="replace")


def send_rtsp(sock: socket.socket, request: str) -> str:
    sock.sendall(request.encode("ascii"))
    response = recv_rtsp(sock)
    first = response.splitlines()[0] if response else ""
    if " 200 " not in first:
        raise RuntimeError(f"RTSP request failed: {first}\n{response}")
    return response


def session_id(response: str) -> str:
    for line in response.splitlines():
        if line.lower().startswith("session:"):
            return line.split(":", 1)[1].split(";", 1)[0].strip()
    raise RuntimeError("RTSP response missing Session header")


def rtp_packet(seq: int, timestamp: int, payload: bytes, ssrc: int) -> bytes:
    header = struct.pack(
        "!BBHII",
        0x80,
        8,
        seq & 0xFFFF,
        timestamp & 0xFFFFFFFF,
        ssrc & 0xFFFFFFFF,
    )
    return header + payload


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--rtsp-port", type=int, required=True)
    parser.add_argument("--base-rtp-port", type=int, required=True)
    parser.add_argument("--legs", type=int, default=1000)
    parser.add_argument("--duration-ms", type=int, default=10000)
    parser.add_argument("--pcma-file", required=True)
    parser.add_argument("--service-id", default="RTP-RING")
    args = parser.parse_args()

    if args.legs < 1 or args.legs > 1800:
        raise SystemExit("legs must be 1..1800")
    if args.duration_ms <= 0 or args.duration_ms % 20:
        raise SystemExit("duration-ms must be a positive multiple of 20")

    pcma = Path(args.pcma_file).read_bytes()
    expected = args.duration_ms * 8
    if len(pcma) != expected:
        raise SystemExit(f"PCMA size {len(pcma)} != expected {expected}")

    frames = len(pcma) // 160
    interaction = str(uuid.uuid4())
    clients: list[tuple[socket.socket, str, str]] = []

    setup_started = time.perf_counter()
    for i in range(args.legs):
        endpoint = f"RTP-CWP-{i + 1:04d}"
        route = f"/record/{endpoint}/tel-rtp-ring"
        uri = f"rtsp://{args.host}:{args.rtsp_port}{route}"
        leg = str(uuid.uuid4())
        sock = socket.create_connection((args.host, args.rtsp_port), timeout=10.0)
        cseq = 1

        send_rtsp(sock, f"OPTIONS {uri} RTSP/1.0\r\nCSeq: {cseq}\r\n\r\n")
        cseq += 1

        sdp = "\r\n".join([
            "v=0",
            "o=- 0 0 IN IP4 127.0.0.1",
            f"s=TELEPHONE {args.service_id} {endpoint} MONO",
            f"c=IN IP4 {args.host}",
            "t=0 0",
            "m=audio 0 RTP/AVP 8",
            "a=rtpmap:8 PCMA/8000",
            f"a=label:tel-rtp-ring-{endpoint.lower()}-mono",
            "a=mid:audio0",
            "",
        ])
        headers = (
            f"X-Interaction-Id: {interaction}\r\n"
            f"X-Leg-Id: {leg}\r\n"
            "X-Audio-Event: RING\r\n"
        )
        response = send_rtsp(
            sock,
            f"ANNOUNCE {uri} RTSP/1.0\r\n"
            f"CSeq: {cseq}\r\n"
            f"{headers}"
            "Content-Type: application/sdp\r\n"
            f"Content-Length: {len(sdp.encode('ascii'))}\r\n\r\n{sdp}",
        )
        cseq += 1
        sid = session_id(response)

        send_rtsp(
            sock,
            f"SETUP {uri} RTSP/1.0\r\n"
            f"CSeq: {cseq}\r\n"
            f"Session: {sid}\r\n"
            f"Transport: RTP/AVP;unicast;client_port={40000 + (i % 20000)}-{40001 + (i % 20000)};mode=record\r\n\r\n",
        )
        cseq += 1

        send_rtsp(
            sock,
            f"RECORD {uri} RTSP/1.0\r\n"
            f"CSeq: {cseq}\r\nSession: {sid}\r\n\r\n",
        )
        cseq += 1
        clients.append((sock, sid, uri))

        if len(clients) % 100 == 0 or len(clients) == args.legs:
            print(f"RTP BURST SETUP sessions={len(clients)}/{args.legs}", flush=True)

    setup_ms = int((time.perf_counter() - setup_started) * 1000)

    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    destinations = [(args.host, args.base_rtp_port + i) for i in range(args.legs)]
    seqs = [1000 + (i % 50000) for i in range(args.legs)]
    timestamps = [0] * args.legs
    ssrcs = [0x52545000 + i for i in range(args.legs)]

    # Real endpoints are not phase-locked. Spread the 1,000 RTP streams
    # across each 20 ms packet interval instead of emitting a 1,000-packet
    # microburst at exactly the same instant. Each stream still sends one
    # packet every 20 ms (50 pps), preserving 50,000 pps aggregate load.
    phase_groups = min(50, args.legs)
    groups: list[list[int]] = [[] for _ in range(phase_groups)]
    for i in range(args.legs):
        groups[i % phase_groups].append(i)

    stream_started = time.perf_counter()
    max_lateness_ms = 0.0
    sent_packets = 0
    for frame in range(frames):
        payload = pcma[frame * 160:(frame + 1) * 160]
        frame_base = stream_started + frame * 0.020
        for group_index, members in enumerate(groups):
            target = frame_base + (group_index * 0.020 / phase_groups)
            while True:
                remaining = target - time.perf_counter()
                if remaining <= 0:
                    if remaining < 0:
                        max_lateness_ms = max(max_lateness_ms, -remaining * 1000.0)
                    break
                if remaining > 0.001:
                    time.sleep(remaining - 0.0005)

            for i in members:
                packet = rtp_packet(seqs[i], timestamps[i], payload, ssrcs[i])
                udp.sendto(packet, destinations[i])
                seqs[i] = (seqs[i] + 1) & 0xFFFF
                timestamps[i] = (timestamps[i] + 160) & 0xFFFFFFFF
                sent_packets += 1

        if frame == 0 or (frame + 1) % 50 == 0 or frame + 1 == frames:
            print(
                f"RTP BURST STREAM frame={frame + 1}/{frames} "
                f"packets={sent_packets}",
                flush=True,
            )

    final_deadline = stream_started + frames * 0.020
    remaining = final_deadline - time.perf_counter()
    if remaining > 0:
        time.sleep(remaining)

    stream_elapsed_ms = int((time.perf_counter() - stream_started) * 1000)
    udp.close()

    close_started = time.perf_counter()
    for i, (sock, sid, uri) in enumerate(clients):
        cseq = 10000
        event_utc = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime()) + ".000Z"
        send_rtsp(
            sock,
            f"SET_PARAMETER {uri} RTSP/1.0\r\n"
            f"CSeq: {cseq}\r\nSession: {sid}\r\n"
            f"X-Audio-Event: HANGUP\r\nX-Event-Utc: {event_utc}\r\n\r\n",
        )
        cseq += 1
        send_rtsp(
            sock,
            f"TEARDOWN {uri} RTSP/1.0\r\n"
            f"CSeq: {cseq}\r\nSession: {sid}\r\n\r\n",
        )
        sock.close()
        if i == 0 or (i + 1) % 100 == 0 or i + 1 == args.legs:
            print(f"RTP BURST CLOSE sessions={i + 1}/{args.legs}", flush=True)

    close_ms = int((time.perf_counter() - close_started) * 1000)
    result = {
        "schema": "audio-system.rtp-ring-burst.v1",
        "legs": args.legs,
        "duration_ms": args.duration_ms,
        "frames_per_leg": frames,
        "packets_sent": sent_packets,
        "phase_groups": phase_groups,
        "payload_bytes_per_leg": len(pcma),
        "total_payload_bytes": len(pcma) * args.legs,
        "setup_ms": setup_ms,
        "stream_elapsed_ms": stream_elapsed_ms,
        "close_ms": close_ms,
        "max_schedule_lateness_ms": round(max_lateness_ms, 3),
        "interaction_id": interaction,
    }
    print("RTP BURST DRIVER: PASS " + json.dumps(result, separators=(",", ":")), flush=True)


if __name__ == "__main__":
    main()
