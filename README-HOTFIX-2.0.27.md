# Recorder PoC Phase 2 — Hotfix 2.0.27

Apply over 2.0.26. No native/plugin rebuild is required.

Run only:

```powershell
.\19-file-manager-loaded-prearm.cmd
```

Expected new diagnostic before worker launch:

`Manifest validation: 100/100 canonical rooted paths exist.`

The load worker then must reach READY before the loaded next-window pre-arm measurement begins.
