# Audio System — Frontend Composition

## Objetivo desta rodada

Compor e tornar testável o frontend independentemente do backend local.

## Mudanças

- `App.tsx` permanece apenas como orquestrador de views e estado compartilhado.
- Adicionada a view `Componentes`, que renderiza componentes reais da aplicação de forma isolada:
  - Status/Summary cards
  - CWP Card
  - Side-A Group
  - Recorder Card / topologia
  - Live Status / Events / Metrics
- Player suporta modo demo local quando `VITE_AUDIO_API_URL` não está definido.
- Quando `VITE_AUDIO_API_URL` for definido, Player passa a consumir:
  - `${VITE_AUDIO_API_URL}/api/timeline`
  - `${VITE_AUDIO_API_URL}/api/preview`
- `vite.config.ts` usa `dist/`, compatível com deploy Vite convencional no Vercel.

## Vercel agora

Use o frontend sem variável `VITE_AUDIO_API_URL`. O Player apresentará dados demo e não tentará acessar o notebook.

## Integração futura

Depois da composição visual, definir no Vercel:

```
VITE_AUDIO_API_URL=https://notebook-jr.tayra-delta.ts.net
```

O backend deverá então fornecer os endpoints e CORS/autenticação apropriados.

## Validação

`npx tsc -b`: PASS.
