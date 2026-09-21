from __future__ import annotations

import unittest

from audio_scenario import resolve_scenario


class ToneScenarioTests(unittest.TestCase):
    def test_continuous_single_interval(self) -> None:
        resolved = resolve_scenario({
            "schema": "audio-system.tone-scenario.v1",
            "duration_ms": 2000,
            "seed": 10,
            "tracks": [{"id": "a", "mode": "continuous", "frequency_hz": 440}],
        })
        track = resolved["tracks"][0]
        self.assertEqual(track["bursts"], [{"on_ms": 2000, "off_ms": 0}])
        self.assertEqual(track["expected_intervals"][0]["duration_ms"], 2000)

    def test_fixed_pulses(self) -> None:
        resolved = resolve_scenario({
            "schema": "audio-system.tone-scenario.v1",
            "duration_ms": 1200,
            "tracks": [{
                "id": "a", "mode": "pulsed", "frequency_hz": 660,
                "on_ms": 200, "off_ms": 200,
            }],
        })
        intervals = resolved["tracks"][0]["expected_intervals"]
        self.assertEqual([item["start_ms"] for item in intervals], [0, 400, 800])

    def test_random_is_reproducible_and_desynchronized(self) -> None:
        scenario = {
            "schema": "audio-system.tone-scenario.v1",
            "duration_ms": 6000,
            "seed": 48291,
            "tracks": [
                {
                    "id": "a", "mode": "random_pulsed", "frequency_hz": 440,
                    "random_start": {"min_ms": 0, "max_ms": 1000},
                    "random_on": {"min_ms": 200, "max_ms": 800},
                    "random_off": {"min_ms": 200, "max_ms": 800},
                },
                {
                    "id": "b", "mode": "random_pulsed", "frequency_hz": 660,
                    "random_start": {"min_ms": 0, "max_ms": 1000},
                    "random_on": {"min_ms": 200, "max_ms": 800},
                    "random_off": {"min_ms": 200, "max_ms": 800},
                },
            ],
        }
        first = resolve_scenario(scenario)
        second = resolve_scenario(scenario)
        self.assertEqual(first, second)
        self.assertNotEqual(first["tracks"][0]["seed"], first["tracks"][1]["seed"])
        self.assertNotEqual(
            first["tracks"][0]["expected_intervals"],
            first["tracks"][1]["expected_intervals"],
        )

    def test_random_schedule_is_100ms_edit_unit_aligned(self) -> None:
        resolved = resolve_scenario({
            "schema": "audio-system.tone-scenario.v1",
            "duration_ms": 3137,
            "seed": 48291,
            "tracks": [{
                "id": "a",
                "mode": "random_pulsed",
                "frequency_hz": 880,
                "random_start": {"min_ms": 17, "max_ms": 583},
                "random_on": {"min_ms": 217, "max_ms": 777},
                "random_off": {"min_ms": 119, "max_ms": 519},
            }],
        })
        track = resolved["tracks"][0]
        self.assertEqual(resolved["duration_ms"] % 100, 0)
        self.assertEqual(track["start_offset_ms"] % 100, 0)
        for burst in track["bursts"]:
            self.assertEqual(burst["on_ms"] % 100, 0)
            self.assertEqual(burst["off_ms"] % 100, 0)

    def test_random_zero_gap_has_no_phantom_silence(self) -> None:
        resolved = resolve_scenario({
            "schema": "audio-system.tone-scenario.v1",
            "duration_ms": 1000,
            "seed": 99,
            "tracks": [{
                "id": "a",
                "mode": "random_pulsed",
                "frequency_hz": 700,
                "random_start": {"min_ms": 0, "max_ms": 0},
                "random_on": {"min_ms": 200, "max_ms": 200},
                "random_off": {"min_ms": 0, "max_ms": 0},
            }],
        })
        track = resolved["tracks"][0]
        self.assertEqual(
            track["expected_intervals"],
            [
                {"start_ms": 0, "end_ms": 200, "duration_ms": 200},
                {"start_ms": 200, "end_ms": 400, "duration_ms": 200},
                {"start_ms": 400, "end_ms": 600, "duration_ms": 200},
                {"start_ms": 600, "end_ms": 800, "duration_ms": 200},
                {"start_ms": 800, "end_ms": 1000, "duration_ms": 200},
            ],
        )
        self.assertTrue(all(item["off_ms"] == 0 for item in track["bursts"]))

    def test_one_frequency_can_target_multiple_tracks(self) -> None:
        resolved = resolve_scenario({
            "schema": "audio-system.tone-scenario.v1",
            "duration_ms": 1000,
            "tracks": [
                {"route_key": "/a", "mode": "continuous", "frequency_hz": 1000},
                {"route_key": "/b", "mode": "continuous", "frequency_hz": 1000},
            ],
        })
        self.assertEqual(resolved["track_count"], 2)
        self.assertEqual([t["frequency_hz"] for t in resolved["tracks"]], [1000.0, 1000.0])


if __name__ == "__main__":
    unittest.main()
