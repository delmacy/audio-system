"""CI probe for read-safe playback from an MXF that is still growing."""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

from playback_data import render_operational_wav


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--logical-track-uuid", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--min-generation", type=int, default=1)
    args = parser.parse_args()

    plan, wav = render_operational_wav(args.logical_track_uuid)
    if not plan.get("open"):
        raise RuntimeError("Expected growing/open MXF playback, but resolver returned a closed file")
    if plan.get("source_scope") != "growing_mxf_confirmed":
        raise RuntimeError(f"Unexpected playback scope: {plan.get('source_scope')}")
    generation = int(plan.get("commit_generation") or 0)
    if generation < args.min_generation:
        raise RuntimeError(
            f"Commit generation {generation} is below required {args.min_generation}"
        )
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
