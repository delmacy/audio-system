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
