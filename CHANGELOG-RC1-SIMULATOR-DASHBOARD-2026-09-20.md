# CHANGELOG — RC1 Simulator Dashboard — 2026-09-20

## Added

- Implemented a new integrated Simulator dashboard view.
- Added global operational mode switch:
  - Captura Real
  - Simulação de Teste
- Added independent Side A and Side B CWP groups.
- Added expandable CWP configuration cards.
- Added separate Recorder and SIP Gateway cards.
- Added active services table for radios and telephones.
- Added live status, event console and metrics panels.
- Added bottom simulation action bar.

## Corrected model

- Removed the idea that Production/Simulation is selected per CWP.
- The operational mode is global to the screen.
- In capture mode, the UI represents the current recorder capture.
- In simulation mode, the UI represents generated test traffic that will be recorded.

## Validation

- `node node_modules/typescript/bin/tsc -b --pretty false` passed.
