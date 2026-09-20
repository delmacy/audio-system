# Frontend refactor — Audio System

Objetivo: separar a UI de domínio que estava concentrada em `src/App.tsx` sem redesenhar a interface.

## Resultado

- `src/App.tsx`: shell/orquestração de views e estado de alto nível (72 linhas; antes 853).
- `src/app/AppSidebar.tsx`: navegação lateral.
- `src/features/simulator/model.ts`: tipos e dados atuais do simulador.
- `src/features/simulator/SimulatorView.tsx`: composição da tela principal do simulador.
- `src/features/simulator/components/`: componentes visuais do domínio:
  - `CwpCard`
  - `SidePanel`
  - `RecorderTopology`
  - `SummaryCard`
  - `ServicePill`
  - `ModeSwitch`
  - `ActiveServicesTable`
  - `EventsPanel`
- `src/features/simulator/views/WorkspaceView.tsx`: views auxiliares relacionadas ao simulador.
- `src/features/player/PlayerView.tsx`: Player/timeline isolado do shell principal.

## Validação

`tsc -b` passa com TypeScript 6.0.3.

O `vite build` e o `oxlint` não executaram no container de validação porque o `node_modules` recebido no ZIP não contém os bindings nativos Linux de Rolldown/Oxlint. Em uma instalação normal do projeto, remova o `node_modules` copiado e execute:

```bash
npm install
npm run build
npm run lint
```

Também foi removido `baseUrl` do `tsconfig.app.json`; no TypeScript 6 ele está depreciado e os aliases continuam definidos por `paths`.
