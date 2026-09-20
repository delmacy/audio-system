# CHANGELOG — RC1 Multi-view Frontend — 2026-09-20

## Added

- Views dedicadas para Serviços, Media Bank, Cenários, Resultados, Gravador, Fault Injection, Logs/Eventos, Exportar e Configurações.
- Navegação lateral atualizada para abrir cada view diretamente.
- Cards e tabelas reutilizando o modelo CWP/TEL/RADIO já existente.
- Painéis de configuração dos CWPs separados por Lado A e Lado B.
- Fault Injection com ações desabilitadas em Captura Real.
- Resultados de execução com botão para abrir o Player.
- Console de logs/eventos usando eventos locais do simulador.

## Changed

- A sidebar deixa de abrir apenas sheets para Serviços/Media Bank/Configurações e passa a navegar para views completas.
- Exportar ganha view própria, mantendo a distinção entre relatório de teste e Evidence Bundle.

## Verified

- TypeScript project check executado com sucesso via `node node_modules/typescript/bin/tsc -b --pretty false`.
