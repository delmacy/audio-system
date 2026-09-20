# Simulator frontend structure

The simulator is organized by composition level instead of a generic `components/` folder.

```
simulator/
├─ elements/   # smallest reusable visual units
├─ lists/      # repeated collections of elements/blocks
├─ blocks/     # visual sections of a page
├─ views/      # ordered page composition
└─ model.ts    # types and demo/config data
```

## Composition chain

```
ServicePill
  ├─ RadioList
  └─ TelephoneList
        ↓
      CwpCard
        ↓
      CwpList
        ↓
      SideBlock
        ↓
SimulatorWorkspaceBlock
        ↓
    SimulatorView
```

The rule is that a view should preferably know blocks, not low-level elements.
