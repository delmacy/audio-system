# Simulator frontend structure

Reusable domain visuals live in `src/representations/`. The simulator only composes them.

```
src/
├─ representations/
│  ├─ cwp/
│  ├─ radio/
│  ├─ telephone/
│  ├─ recorder/
│  └─ player/
└─ features/simulator/
   ├─ elements/   # generic simulator-only visual elements
   ├─ lists/      # simulator-specific collections
   ├─ blocks/     # page sections
   ├─ views/      # ordered page composition
   └─ model.ts
```

Rule: entity visuals belong to `representations/<entity>/`; a feature chooses the representation appropriate to its context.
