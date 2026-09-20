# Phase 15 Acceptance — Web Player Shell

## Required checks

1. `web/player/index.html` exists.
2. `web/player/assets/player.css` exists.
3. `web/player/assets/player.js` exists.
4. `web/player/fixtures/playback-plan.sample.json` exists.
5. Fixture has `logical_track_uuid`, `segments`, `events`, and `service_tree`.
6. At least one media segment and one explicit gap are present.
7. UI text includes `RADIO 121.500`, `LogicalTrackUUID`, `Gaps explícitos`, and `Exportar`.
8. No base RX/TX service split is present in the fixture.

## Result

This phase is `MATERIALIZED`; it becomes `VALIDATED` only after the smoke is run on Windows or in a browser-capable environment.
