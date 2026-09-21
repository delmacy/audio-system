"""Deterministic audio test-signal generator for the Audio System recorder lab.

Produces raw G.711 A-law (PCMA, 8 kHz mono) for RTP payload injection and,
optionally, a PCM16 WAV copy for listening/inspection. No external codec or
FFmpeg dependency is required.
"""

from __future__ import annotations

import argparse
import json
import math
import struct
import wave
from pathlib import Path

PCMA_SAMPLE_RATE = 8000
PCMA_BITS_PER_SAMPLE = 8
PCMA_CHANNELS = 1
PCMA_RTP_PAYLOAD_TYPE = 8
PCMA_CODEC_PROFILE = {
    "codec": "CCITT_ALAW",
    "standard": "ITU-T G.711 A-law",
    "rtp_encoding": "PCMA",
    "sample_rate_hz": PCMA_SAMPLE_RATE,
    "bits_per_sample": PCMA_BITS_PER_SAMPLE,
    "channels": PCMA_CHANNELS,
    "channel_layout": "mono",
    "rtp_payload_type": PCMA_RTP_PAYLOAD_TYPE,
}
PCM16_MAX = 32767
ALAW_SEG_END = (0x1F, 0x3F, 0x7F, 0xFF, 0x1FF, 0x3FF, 0x7FF, 0xFFF)


def linear16_to_alaw(sample: int) -> int:
    """Encode one signed PCM16 sample as ITU-T G.711 A-law."""
    sample = max(-32768, min(32767, int(sample)))
    sample >>= 3

    if sample >= 0:
        mask = 0xD5
    else:
        mask = 0x55
        sample = -sample - 1

    segment = 8
    for index, end in enumerate(ALAW_SEG_END):
        if sample <= end:
            segment = index
            break

    if segment >= 8:
        value = 0x7F
    else:
        value = segment << 4
        if segment < 2:
            value |= (sample >> 1) & 0x0F
        else:
            value |= (sample >> segment) & 0x0F
    return value ^ mask


def generate_sine_pcm16(
    *,
    frequency_hz: float,
    duration_seconds: float,
    level_dbfs: float,
    sample_rate: int = PCMA_SAMPLE_RATE,
    phase_degrees: float = 0.0,
) -> list[int]:
    if not (1.0 <= frequency_hz < sample_rate / 2):
        raise ValueError(f"frequency_hz must be >= 1 and below Nyquist ({sample_rate / 2:g} Hz)")
    if duration_seconds <= 0:
        raise ValueError("duration_seconds must be > 0")
    if level_dbfs > 0:
        raise ValueError("level_dbfs must be <= 0 dBFS")
    if level_dbfs < -90:
        raise ValueError("level_dbfs must be >= -90 dBFS")

    count = max(1, int(round(duration_seconds * sample_rate)))
    amplitude = PCM16_MAX * (10.0 ** (level_dbfs / 20.0))
    phase = math.radians(phase_degrees)
    step = 2.0 * math.pi * frequency_hz / sample_rate

    return [
        int(round(amplitude * math.sin(phase + step * index)))
        for index in range(count)
    ]


def pcm16_bytes(samples: list[int]) -> bytes:
    return b"".join(struct.pack("<h", sample) for sample in samples)


def pcma_bytes(samples: list[int]) -> bytes:
    return bytes(linear16_to_alaw(sample) for sample in samples)


def write_wav(path: Path, samples: list[int], sample_rate: int = PCMA_SAMPLE_RATE) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sample_rate)
        handle.writeframes(pcm16_bytes(samples))


def generate_tone(
    *,
    frequency_hz: float,
    duration_seconds: float,
    level_dbfs: float,
    pcma_path: Path,
    wav_path: Path | None = None,
    phase_degrees: float = 0.0,
) -> dict:
    samples = generate_sine_pcm16(
        frequency_hz=frequency_hz,
        duration_seconds=duration_seconds,
        level_dbfs=level_dbfs,
        phase_degrees=phase_degrees,
    )
    payload = pcma_bytes(samples)
    pcma_path.parent.mkdir(parents=True, exist_ok=True)
    pcma_path.write_bytes(payload)
    if wav_path is not None:
        write_wav(wav_path, samples)

    return {
        "schema": "audio-system.test-tone.v1",
        "waveform": "sine",
        "frequency_hz": frequency_hz,
        "duration_seconds": duration_seconds,
        "level_dbfs": level_dbfs,
        "codec_profile": dict(PCMA_CODEC_PROFILE),
        "codec": PCMA_CODEC_PROFILE["codec"],
        "standard": PCMA_CODEC_PROFILE["standard"],
        "rtp_encoding": PCMA_CODEC_PROFILE["rtp_encoding"],
        "sample_rate_hz": PCMA_SAMPLE_RATE,
        "bits_per_sample": PCMA_BITS_PER_SAMPLE,
        "channels": PCMA_CHANNELS,
        "channel_layout": "mono",
        "rtp_payload_type": PCMA_RTP_PAYLOAD_TYPE,
        "sample_count": len(samples),
        "pcma_bytes": len(payload),
        "pcma_path": str(pcma_path.resolve()),
        "wav_path": str(wav_path.resolve()) if wav_path is not None else None,
    }


def selftest() -> None:
    assert linear16_to_alaw(0) == 0xD5, "A-law silence code must be 0xD5"
    samples = generate_sine_pcm16(
        frequency_hz=1000,
        duration_seconds=1.0,
        level_dbfs=-12.0,
    )
    assert len(samples) == 8000
    encoded = pcma_bytes(samples)
    assert len(encoded) == 8000
    assert len(set(encoded)) > 4
    assert PCMA_CODEC_PROFILE == {
        "codec": "CCITT_ALAW",
        "standard": "ITU-T G.711 A-law",
        "rtp_encoding": "PCMA",
        "sample_rate_hz": 8000,
        "bits_per_sample": 8,
        "channels": 1,
        "channel_layout": "mono",
        "rtp_payload_type": 8,
    }
    print("AUDIO GENERATOR SELFTEST: PASS")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate deterministic recorder test audio")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--frequency", type=float, default=1000.0, help="Sine frequency in Hz")
    parser.add_argument("--duration", type=float, default=2.0, help="Duration in seconds")
    parser.add_argument("--level-dbfs", type=float, default=-12.0, help="Peak level in dBFS (<= 0)")
    parser.add_argument("--phase-degrees", type=float, default=0.0)
    parser.add_argument("--pcma", help="Output raw PCMA/A-law file")
    parser.add_argument("--wav", help="Optional PCM16 WAV preview")
    args = parser.parse_args()

    if args.selftest:
        selftest()
        return
    if not args.pcma:
        parser.error("--pcma is required unless --selftest is used")

    result = generate_tone(
        frequency_hz=args.frequency,
        duration_seconds=args.duration,
        level_dbfs=args.level_dbfs,
        phase_degrees=args.phase_degrees,
        pcma_path=Path(args.pcma),
        wav_path=Path(args.wav) if args.wav else None,
    )
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
