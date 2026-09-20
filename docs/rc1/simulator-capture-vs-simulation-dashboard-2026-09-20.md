# RC1 Integrated Frontend — Simulator Capture vs Simulation Dashboard

This patch implements the corrected Simulator dashboard concept:

- `Captura Real` is the current recorder capture/monitoring mode.
- `Simulação de Teste` is the traffic generation mode used to create audio/signaling that will be recorded for tests.
- Production/simulation is not a per-CWP toggle. It is a global operational mode for the screen.
- CWP cards render the configuration corresponding to the active global mode.
- Each CWP card can be expanded to inspect its configuration: console IP, active radios, active telephones, profile, notes and service list.
- The Recorder is rendered as an independent card, not embedded inside a CWP.
- The SIP Gateway is rendered as an independent card for telephony/radio-adapter translation.
- Side A and Side B are rendered as separate groups, each with its own CWP cards.

## Domain rules preserved

- CWP direct recording path remains CWP → Recorder via RTSP/RTP.
- Gateway is only for SIP/telephony and physical/legacy radio adapters.
- Simulation generates communications that are recorded for test.
- Capture mode observes the current recorder and does not generate artificial media.
- Fixture/mock UI is not evidence.
- Live buffer is not evidence.

## Implemented files

- `web/player-app/src/App.tsx`
- `web/player-app/src/App.css`
- `docs/rc1/simulator-capture-vs-simulation-dashboard-2026-09-20.md`
- `CHANGELOG-RC1-SIMULATOR-DASHBOARD-2026-09-20.md`

## Validation

Static TypeScript validation was run with:

```powershell
node node_modules/typescript/bin/tsc -b --pretty false
```

It passed in the working copy.

The normal `npm run build` script was not used in this Linux container because this uploaded repository carries Windows-oriented `node_modules` bindings and npm resolves a mismatched TypeScript path here. On the user's Windows machine, run the ordinary build after applying the patch:

```powershell
cd web\player-app
npm install
npm run build
```
