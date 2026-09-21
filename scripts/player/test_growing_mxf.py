from __future__ import annotations

import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from playback_data import (
    EDIT_UNIT_NS,
    SAMPLE_RATE,
    SAMPLES_PER_EDIT_UNIT,
    _decode_growing_pcm,
)


GC_PREFIX = bytes.fromhex("060e2b34010201010d010301")


def ber(value: int) -> bytes:
    if value < 0x80:
        return bytes([value])
    raw = value.to_bytes((value.bit_length() + 7) // 8, "big")
    return bytes([0x80 | len(raw)]) + raw


def klv(key: bytes, value: bytes) -> bytes:
    return key + ber(len(value)) + value


def essence_key(track_ordinal: int) -> bytes:
    return GC_PREFIX + bytes([0x16, 0x02, 0x08, track_ordinal])


class GrowingMxfPlaybackTests(unittest.TestCase):
    def test_reads_only_selected_track_and_ignores_structural_gap_payload(self) -> None:
        track1_audio = bytes([0x55]) * SAMPLES_PER_EDIT_UNIT
        structural_filler = bytes([0xD5]) * SAMPLES_PER_EDIT_UNIT
        track2_audio = bytes([0x35]) * SAMPLES_PER_EDIT_UNIT
        stream = b"".join([
            klv(bytes.fromhex("060e2b34020501010d01020101020400"), b"metadata"),
            klv(essence_key(1), track1_audio),
            klv(essence_key(2), track2_audio),
            klv(essence_key(1), structural_filler),
            klv(essence_key(2), track2_audio),
            klv(essence_key(1), track1_audio),
        ])

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "growing.mxf.partial"
            path.write_bytes(stream)
            window_start = datetime(2026, 9, 21, 12, 0, 0, tzinfo=timezone.utc)
            resolved = {
                "mxf": path,
                "flushed_bytes": len(stream),
                "track": {"track_index": 0},
                "timeline_origin_utc": window_start.isoformat().replace("+00:00", "Z"),
                "intervals": [
                    {
                        "start_utc": window_start.isoformat().replace("+00:00", "Z"),
                        "end_utc": (window_start + timedelta(milliseconds=100)).isoformat().replace("+00:00", "Z"),
                    },
                    {
                        "start_utc": (window_start + timedelta(milliseconds=200)).isoformat().replace("+00:00", "Z"),
                        "end_utc": (window_start + timedelta(milliseconds=300)).isoformat().replace("+00:00", "Z"),
                    },
                ],
            }

            pcm = _decode_growing_pcm(resolved)

        self.assertEqual(len(pcm) // 2, 2 * SAMPLES_PER_EDIT_UNIT)
        self.assertNotEqual(pcm, b"\x00" * len(pcm))
        first = pcm[: SAMPLES_PER_EDIT_UNIT * 2]
        second = pcm[SAMPLES_PER_EDIT_UNIT * 2 :]
        self.assertEqual(first, second)

    def test_stops_after_media_duration_confirmed_by_audit(self) -> None:
        audio = bytes([0xD5]) * SAMPLES_PER_EDIT_UNIT
        stream = b"".join([
            klv(essence_key(1), audio),
            klv(essence_key(1), audio),
            klv(essence_key(1), audio),
        ])

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "growing.mxf.partial"
            path.write_bytes(stream)
            window_start = datetime(2026, 9, 21, 12, 0, 0, tzinfo=timezone.utc)
            resolved = {
                "mxf": path,
                "flushed_bytes": len(stream),
                "track": {"track_index": 0},
                "timeline_origin_utc": window_start.isoformat().replace("+00:00", "Z"),
                "intervals": [{
                    "start_utc": window_start.isoformat().replace("+00:00", "Z"),
                    "end_utc": (window_start + timedelta(milliseconds=200)).isoformat().replace("+00:00", "Z"),
                }],
            }

            pcm = _decode_growing_pcm(resolved)

        self.assertEqual(len(pcm) // 2, SAMPLE_RATE // 5)
        self.assertNotEqual(pcm, b"\x00" * len(pcm))




def test_operational_plan_exposes_growing_watermark_fields() -> None:
    source = (ROOT / "scripts" / "player" / "playback_data.py").read_text(encoding="utf-8")
    assert '"committed_position_ns": resolved.get("committed_position_ns")' in source
    assert '"flushed_bytes": resolved.get("flushed_bytes")' in source

if __name__ == "__main__":
    unittest.main()
