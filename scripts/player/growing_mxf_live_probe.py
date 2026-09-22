"""CI probe for read-safe playback from an MXF that is still growing."""

from __future__ import annotations

import argparse
import json
import struct
import time
from pathlib import Path

from playback_data import render_operational_wav


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--logical-track-uuid", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--min-generation", type=int, default=1)
    parser.add_argument("--wait-seconds", type=float, default=0.0)
    args = parser.parse_args()

    deadline = time.monotonic() + max(0.0, args.wait_seconds)
    last_error: Exception | None = None
    while True:
        try:
            plan, wav = render_operational_wav(args.logical_track_uuid)
            generation = int(plan.get("commit_generation") or 0)
            if generation < args.min_generation:
                raise LookupError(
                    f"Commit generation {generation} is below required {args.min_generation}"
                )
            break
        except (LookupError, FileNotFoundError, ValueError, json.JSONDecodeError) as exc:
            last_error = exc
            if time.monotonic() >= deadline:
                raise RuntimeError(
                    f"Growing MXF did not become playback-ready within "
                    f"{args.wait_seconds:g}s: {last_error}"
                ) from exc
            time.sleep(0.1)
    if not plan.get("open"):
        raise RuntimeError("Expected growing/open MXF playback, but resolver returned a closed file")
    if plan.get("source_scope") != "growing_mxf_confirmed":
        raise RuntimeError(f"Unexpected playback scope: {plan.get('source_scope')}")
    generation = int(plan.get("commit_generation") or 0)
    if not plan.get("confirmed_until_utc"):
        raise RuntimeError("Growing playback did not expose confirmed_until_utc")
    if len(wav) <= 44 or wav[:4] != b"RIFF" or wav[8:12] != b"WAVE":
        raise RuntimeError("Growing playback did not produce a valid non-empty WAV")

    data_size = struct.unpack_from("<I", wav, 40)[0]
    pcm = wav[44:44 + data_size]
    if not pcm:
        raise RuntimeError("Growing playback WAV contains no PCM payload")
    if not any(pcm):
        raise RuntimeError("Growing playback PCM is entirely zero; expected recorded PCMA media")

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(wav)

    result = {
        "status": "PASS",
        "open": True,
        "source_scope": plan["source_scope"],
        "commit_generation": generation,
        "committed_position_ns": int(plan.get("committed_position_ns") or 0),
        "confirmed_until_utc": plan["confirmed_until_utc"],
        "from_utc": plan["from_utc"],
        "to_utc": plan["to_utc"],
        "wav_bytes": len(wav),
        "pcm_bytes": len(pcm),
        "output": str(output.resolve()),
    }
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
