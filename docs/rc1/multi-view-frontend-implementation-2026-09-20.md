# RC1 Multi-view Frontend Implementation — 2026-09-20

Este pacote expande o frontend integrado do Recorder/Simulador com views operacionais além do Dashboard e Player.

## Views implementadas

- Simulador: dashboard de Captura Real / Simulação de Teste.
- Player: timeline histórica com grupos CWP/TEL/RADIO.
- Serviços: configuração de CWP, rádios, telefones, IPs e serviços por lado A/B.
- Media Bank: inventário visual de clips, tons e conversas usados em simulação.
- Cenários: seleção e preparação de cenários de simulação.
- Resultados: histórico de runs com link para abrir Player.
- Gravador: painel do gravador corrente, pipeline, storage e integridade.
- Falhas: fault injection controlado, desabilitado em Captura Real.
- Logs e Eventos: console operacional filtrável futuramente por P0/P1/P2/P3.
- Exportar: preparação de relatório e Evidence Bundle quando aplicável.
- Configurações: modo operacional global e regras invariantes.

## Correção conceitual preservada

O modo operacional é global:

- Captura Real: observa a captura feita pelo gravador corrente.
- Simulação de Teste: gera áudio/comunicações artificiais para serem gravadas e testadas.

Não existe alternância Produção/Simulação por CWP.

## Regras preservadas

- CWP direto para Recorder via RTSP/RTP.
- Gateway apenas para SIP/telefonia e rádio físico/legado.
- 1 serviço = 1 fluxo mono = 1 LogicalTrackUUID = 1 track MXF.
- RX/TX não são trilhas base.
- Live buffer, fixture e silêncio sintético não são evidência.
- Gate NOT_RUN nunca vira PASS.

## Validação local executada

```powershell
node node_modules/typescript/bin/tsc -b --pretty false
```

Resultado: PASS no ambiente de geração.
