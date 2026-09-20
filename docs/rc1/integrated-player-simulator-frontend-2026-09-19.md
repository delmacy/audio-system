# RC1 Integrated Player + Communication Simulator Frontend

## Objetivo

Integrar, no mesmo frontend React/Vite, duas views operacionais:

1. **Player** — timeline multitrilha clara para revisão de gravações por CWP/TEL/RADIO.
2. **Simulador** — painel de controle para cenários de comunicação, topologia, status ao vivo, eventos, métricas e ações de cenário.

A navegação fica unificada na sidebar. O usuário alterna entre **Player** e **Simulador** sem sair da aplicação.

## Escopo implementado

- Nova navegação lateral com item **Player** e item **Simulador**.
- Preservação da tela do Player com grupos CWP/TEL/RADIO, checkboxes por grupo/trilha, playhead vermelho, span selecionado e sombreado externo nas trilhas.
- Nova view conceitual/funcional do **Communication Simulator** com:
  - topologia CWP/TEL/RADIO/Gateway/Recorder;
  - status ao vivo;
  - console de eventos;
  - métricas em tempo real;
  - resumo de atividade dos serviços;
  - dock inferior com Start/Pause/Stop/Inject Fault/Export Report/Open Player.
- Fallback visual quando `runs`, `media` ou índice SQLite ainda não existem no repositório local.
- Fixture local do Player marcada como `ui_mock`, sem confundir com evidência.

## Decisões preservadas

- CWP direto para Recorder via RTSP/RTP.
- Gateway apenas para SIP/telefonia e rádio físico/legado.
- 1 serviço = 1 fluxo mono = 1 LogicalTrackUUID = 1 track MXF.
- RX/TX não é track base.
- Live buffer não é evidência.
- Fixture visual não é evidência.
- Silence/gap sintético não é áudio gravado.
- NOT_RUN nunca vira PASS.

## Arquivos principais alterados

- `web/player-app/src/App.tsx`
- `web/player-app/src/App.css`
- `web/player-app/src/timeline-model.ts`

## Validação feita

Foi executado:

```powershell
node node_modules/typescript/bin/tsc -b --pretty false
```

Resultado: TypeScript passou.

O `npm run build` não pôde ser concluído dentro do ambiente Linux desta sessão porque o `node_modules` enviado no ZIP contém dependências opcionais nativas do Windows/Rolldown/Vite e não possui o binding Linux correspondente. No Windows local, rodar:

```powershell
cd web\player-app
npm install
npm run build
```

Se o objetivo for manter o pacote sem `node_modules`, basta excluir `node_modules` e rodar `npm install` novamente.
