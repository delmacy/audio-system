"""Resolve reproducible multi-track tone scenarios for the recorder simulator.

The planner turns user-facing modes (continuous, pulsed, random_pulsed) into a
concrete 20 ms-aligned schedule. Random scenarios are deterministic from the
scenario seed so a failing recording can be reproduced exactly.
"""

from __future__ import annotations

import argparse
import json
import random
from pathlib import Path
from typing import Any

RTP_FRAME_MS = 20
# The current A-law MXF mapping uses edit_rate 10/1. Scenario boundaries must
# not split an edit unit; RTP packets inside active intervals remain 20 ms.
MXF_AUDIO_EDIT_UNIT_MS = 100
SCHEMA = "audio-system.tone-scenario.v1"
RESOLVED_SCHEMA = "audio-system.tone-scenario-resolved.v1"
MODES = {"continuous", "pulsed", "random_pulsed"}
AUDIO_FORMAT = {
    "codec": "CCITT_ALAW",
    "standard": "ITU-T G.711 A-law",
    "rtp_encoding": "PCMA",
    "sample_rate_hz": 8000,
    "bits_per_sample": 8,
    "channels": 1,
    "channel_layout": "mono",
    "rtp_payload_type": 8,
}


def _validate_audio_format(value: Any) -> dict:
    if value is None:
        return dict(AUDIO_FORMAT)
    if not isinstance(value, dict):
        raise ValueError("audio_format must be an object")
    for key, expected in AUDIO_FORMAT.items():
        if key in value and value[key] != expected:
            raise ValueError(
                f"Unsupported audio_format.{key}={value[key]!r}; required {expected!r}"
            )
    return dict(AUDIO_FORMAT)


def _positive_int(value: Any, name: str, *, allow_zero: bool = False) -> int:
    result = int(value)
    minimum = 0 if allow_zero else 1
    if result < minimum:
        raise ValueError(f"{name} must be >= {minimum}")
    return result


def _quantize_ms(value: int, *, minimum: int = MXF_AUDIO_EDIT_UNIT_MS) -> int:
    if value <= 0:
        return 0
    quantized = int(round(value / MXF_AUDIO_EDIT_UNIT_MS)) * MXF_AUDIO_EDIT_UNIT_MS
    return max(minimum, quantized)


def _range_ms(track: dict, name: str, default_min: int, default_max: int) -> tuple[int, int]:
    value = track.get(name)
    if value is None:
        lo, hi = default_min, default_max
    elif isinstance(value, dict):
        lo = _positive_int(value.get("min_ms", default_min), f"{name}.min_ms", allow_zero=True)
        hi = _positive_int(value.get("max_ms", default_max), f"{name}.max_ms", allow_zero=True)
    else:
        lo = hi = _positive_int(value, name, allow_zero=True)
    if hi < lo:
        raise ValueError(f"{name}.max_ms must be >= {name}.min_ms")
    return _quantize_ms(lo, minimum=0), _quantize_ms(hi, minimum=0)


def _draw_ms(rng: random.Random, bounds: tuple[int, int], *, minimum: int = RTP_FRAME_MS) -> int:
    lo, hi = bounds
    if hi <= lo:
        return max(minimum, lo) if lo > 0 else 0
    steps = max(0, (hi - lo) // MXF_AUDIO_EDIT_UNIT_MS)
    return max(minimum, lo + rng.randint(0, steps) * MXF_AUDIO_EDIT_UNIT_MS)


def _resolve_start_offset(track: dict, rng: random.Random) -> int:
    if "start_offset_ms" in track:
        return _quantize_ms(_positive_int(track["start_offset_ms"], "start_offset_ms", allow_zero=True), minimum=0)
    bounds = _range_ms(track, "random_start", 0, 0)
    return _draw_ms(rng, bounds, minimum=0)


def _fixed_schedule(start_ms: int, duration_ms: int, on_ms: int, off_ms: int) -> tuple[list[dict], list[dict]]:
    bursts: list[dict] = []
    intervals: list[dict] = []
    cursor = start_ms
    while cursor < duration_ms:
        active = min(on_ms, duration_ms - cursor)
        active = _quantize_ms(active)
        if cursor + active > duration_ms:
            active = duration_ms - cursor
        if active <= 0:
            break
        next_cursor = cursor + active
        gap = min(off_ms, max(0, duration_ms - next_cursor))
        gap = _quantize_ms(gap, minimum=0)
        if next_cursor + gap > duration_ms:
            gap = duration_ms - next_cursor
        bursts.append({"on_ms": active, "off_ms": gap})
        intervals.append({"start_ms": cursor, "end_ms": cursor + active, "duration_ms": active})
        cursor = next_cursor + gap
        if off_ms == 0 and cursor < duration_ms:
            # A zero-gap pulsed schedule is equivalent to one continuous active interval.
            remaining = duration_ms - cursor
            if remaining > 0:
                bursts[-1]["on_ms"] += remaining
                intervals[-1]["end_ms"] += remaining
                intervals[-1]["duration_ms"] += remaining
            break
    return bursts, intervals


def _random_schedule(
    start_ms: int,
    duration_ms: int,
    rng: random.Random,
    on_bounds: tuple[int, int],
    off_bounds: tuple[int, int],
) -> tuple[list[dict], list[dict]]:
    bursts: list[dict] = []
    intervals: list[dict] = []
    cursor = start_ms
    while cursor < duration_ms:
        on_ms = _draw_ms(rng, on_bounds)
        active = min(on_ms, duration_ms - cursor)
        active = _quantize_ms(active)
        if cursor + active > duration_ms:
            active = duration_ms - cursor
        if active <= 0:
            break
        intervals.append({"start_ms": cursor, "end_ms": cursor + active, "duration_ms": active})
        after = cursor + active
        off_ms = _draw_ms(rng, off_bounds, minimum=0)
        gap = min(off_ms, max(0, duration_ms - after))
        gap = _quantize_ms(gap, minimum=0)
        if after + gap > duration_ms:
            gap = duration_ms - after
        bursts.append({"on_ms": active, "off_ms": gap})
        cursor = after + gap
    return bursts, intervals


def resolve_track(track: dict, *, duration_ms: int, scenario_seed: int, index: int) -> dict:
    mode = str(track.get("mode", "continuous")).lower()
    if mode not in MODES:
        raise ValueError(f"Unsupported tone mode: {mode}")

    frequency_hz = float(track.get("frequency_hz", 1000.0))
    if not 1.0 <= frequency_hz < 4000.0:
        raise ValueError("frequency_hz must be >= 1 and < 4000 for 8 kHz PCMA")
    level_dbfs = float(track.get("level_dbfs", -12.0))
    if level_dbfs > 0 or level_dbfs < -90:
        raise ValueError("level_dbfs must be between -90 and 0")

    track_seed = int(track.get("seed", scenario_seed + index * 1_000_003))
    rng = random.Random(track_seed)
    start_ms = _resolve_start_offset(track, rng)
    if start_ms >= duration_ms:
        raise ValueError(f"track start offset {start_ms} ms is outside scenario duration {duration_ms} ms")

    if mode == "continuous":
        bursts, intervals = _fixed_schedule(start_ms, duration_ms, duration_ms - start_ms, 0)
    elif mode == "pulsed":
        on_ms = _quantize_ms(_positive_int(track.get("on_ms", 500), "on_ms"))
        off_ms = _quantize_ms(_positive_int(track.get("off_ms", 500), "off_ms", allow_zero=True), minimum=0)
        bursts, intervals = _fixed_schedule(start_ms, duration_ms, on_ms, off_ms)
    else:
        on_bounds = _range_ms(track, "random_on", 300, 1200)
        off_bounds = _range_ms(track, "random_off", 200, 900)
        if on_bounds[0] <= 0:
            raise ValueError("random_on.min_ms must be > 0")
        bursts, intervals = _random_schedule(start_ms, duration_ms, rng, on_bounds, off_bounds)

    if not bursts:
        raise ValueError("Track resolved to an empty schedule")

    return {
        **track,
        "mode": mode,
        "frequency_hz": frequency_hz,
        "level_dbfs": level_dbfs,
        "seed": track_seed,
        "audio_format": dict(AUDIO_FORMAT),
        "start_offset_ms": start_ms,
        "bursts": bursts,
        "expected_intervals": intervals,
    }


def resolve_scenario(scenario: dict) -> dict:
    schema = scenario.get("schema", SCHEMA)
    if schema != SCHEMA:
        raise ValueError(f"Unsupported scenario schema: {schema}")
    duration_ms = _quantize_ms(_positive_int(scenario.get("duration_ms", 10_000), "duration_ms"))
    audio_format = _validate_audio_format(scenario.get("audio_format"))
    seed = int(scenario.get("seed", 1))
    tracks = scenario.get("tracks")
    if not isinstance(tracks, list) or not tracks:
        raise ValueError("scenario.tracks must be a non-empty array")

    resolved = [
        resolve_track(dict(track), duration_ms=duration_ms, scenario_seed=seed, index=index)
        for index, track in enumerate(tracks)
    ]
    return {
        "schema": RESOLVED_SCHEMA,
        "source_schema": SCHEMA,
        "duration_ms": duration_ms,
        "audio_format": audio_format,
        "seed": seed,
        "track_count": len(resolved),
        "tracks": resolved,
    }


def selftest() -> None:
    scenario = {
        "schema": SCHEMA,
        "duration_ms": 5000,
        "seed": 48291,
        "tracks": [
            {"id": "a", "mode": "continuous", "frequency_hz": 440},
            {"id": "b", "mode": "pulsed", "frequency_hz": 660, "on_ms": 400, "off_ms": 200},
            {
                "id": "c",
                "mode": "random_pulsed",
                "frequency_hz": 880,
                "random_start": {"min_ms": 0, "max_ms": 800},
                "random_on": {"min_ms": 200, "max_ms": 600},
                "random_off": {"min_ms": 100, "max_ms": 500},
            },
        ],
    }
    one = resolve_scenario(scenario)
    two = resolve_scenario(scenario)
    assert one == two
    assert one["audio_format"] == AUDIO_FORMAT
    assert one["tracks"][0]["audio_format"] == AUDIO_FORMAT
    assert one["tracks"][0]["expected_intervals"] == [{"start_ms": 0, "end_ms": 5000, "duration_ms": 5000}]
    assert len(one["tracks"][1]["bursts"]) > 2
    assert one["tracks"][2]["start_offset_ms"] % MXF_AUDIO_EDIT_UNIT_MS == 0
    assert len(one["tracks"][2]["expected_intervals"]) > 1
    print("TONE SCENARIO SELFTEST: PASS")


def main() -> None:
    parser = argparse.ArgumentParser(description="Resolve deterministic multi-track tone schedules")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--scenario", help="Input scenario JSON")
    parser.add_argument("--output", help="Optional resolved JSON output")
    args = parser.parse_args()

    if args.selftest:
        selftest()
        return
    if not args.scenario:
        parser.error("--scenario is required unless --selftest is used")

    scenario = json.loads(Path(args.scenario).read_text(encoding="utf-8-sig"))
    resolved = resolve_scenario(scenario)
    text = json.dumps(resolved, ensure_ascii=False, indent=2)
    if args.output:
        Path(args.output).write_text(text + "\n", encoding="utf-8")
    print(text)


if __name__ == "__main__":
    main()
