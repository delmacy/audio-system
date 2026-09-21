from __future__ import annotations

import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from playback_data import (
    EDIT_UNIT_NS,
    SAMPLE_RATE,
    SAMPLES_PER_EDIT_UNIT,
    _decode_growing_window,
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
    def test_reads_only_selected_track_and_preserves_gap_edit_unit(self) -> None:
        track1_audio = bytes([0xD5]) * SAMPLES_PER_EDIT_UNIT
        track2_audio = bytes([0x55]) * SAMPLES_PER_EDIT_UNIT
        stream = b"".join([
            klv(bytes.fromhex("060e2b34020501010d01020101020400"), b"metadata"),
            klv(essence_key(1), track1_audio),
            klv(essence_key(2), track2_audio),
            klv(essence_key(1), b""),
            klv(essence_key(2), track2_audio),
        ])

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "growing.mxf.partial"
            path.write_bytes(stream)
            window_start = datetime(2026, 9, 21, 12, 0, 0, tzinfo=timezone.utc)
            resolved = {
                "mxf": path,
                "window_start_utc": window_start.isoformat().replace("+00:00", "Z"),
                "committed_position_ns": 2 * EDIT_UNIT_NS,
                "flushed_bytes": len(stream),
                "track": {"track_index": 0},
            }

            pcm = _decode_growing_window(
                resolved,
                window_start,
                window_start + timedelta(milliseconds=200),
            )

        samples = len(pcm) // 2
        self.assertEqual(samples, SAMPLE_RATE // 5)
        first_unit = pcm[: SAMPLES_PER_EDIT_UNIT * 2]
        second_unit = pcm[SAMPLES_PER_EDIT_UNIT * 2 :]
        self.assertNotEqual(first_unit, b"\x00" * len(first_unit))
        self.assertEqual(second_unit, b"\x00" * len(second_unit))

    def test_never_decodes_beyond_committed_position(self) -> None:
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
                "window_start_utc": window_start.isoformat().replace("+00:00", "Z"),
                "committed_position_ns": 2 * EDIT_UNIT_NS,
                "flushed_bytes": len(stream),
                "track": {"track_index": 0},
            }

            pcm = _decode_growing_window(
                resolved,
                window_start,
                window_start + timedelta(milliseconds=300),
            )

        committed_bytes = 2 * SAMPLES_PER_EDIT_UNIT * 2
        self.assertNotEqual(pcm[:committed_bytes], b"\x00" * committed_bytes)
        self.assertEqual(pcm[committed_bytes:], b"\x00" * (len(pcm) - committed_bytes))


if __name__ == "__main__":
    unittest.main()
