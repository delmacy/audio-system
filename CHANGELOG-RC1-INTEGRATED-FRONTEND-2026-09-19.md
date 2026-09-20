# CHANGELOG — RC1 Integrated Frontend — 2026-09-19

## Added

- Integrated sidebar navigation between Player and Communication Simulator.
- Communication Simulator view with topology diagram, live status, event console, metrics and scenario control dock.
- Local UI fixture fallback for Player when `runs`, `media`, `media-bank` or SQLite index are absent.
- `ui_mock` source type in timeline model to prevent fixture data from being confused with evidence.

## Changed

- Player shell now distinguishes `FIXTURE LOCAL` from `MXF FECHADO`.
- Preview/playback refuses `ui_mock` data as real MXF audio.
- Sidebar keeps Player, Simulador, Configurações, Exportar, Filtros, Sessão and Preferências in one app shell.

## Validation

- TypeScript project check passed using local compiler entrypoint.
- Vite build was not executed successfully in this Linux sandbox because the uploaded `node_modules` contains platform-specific optional native bindings from the user's Windows environment. Reinstall dependencies locally before building.
