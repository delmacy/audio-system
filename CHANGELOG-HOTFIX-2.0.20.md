# Hotfix 2.0.20 — pre-armed file/window manager capacity gate

- Adds `17-file-manager-prearm-capacity.cmd`.
- Proves that 100 required files can be physically created, manager-owned, locked and ARMED before a logical recording window begins.
- Separates physical creation timestamps from logical recording-window timestamps.
- Enforces a 100% READY barrier before T0 and forbids CreateNew on the boundary path.
- Measures per-file arming margins and activation-dispatch span.
- Adds `BOUNDARY_SPILL_REQUIRED` fallback semantics: keep prior writers active rather than lose required media.
- Capacity probe intentionally does not claim to produce valid MXF; actual MXF handle integration proceeds with durability/storage work.
