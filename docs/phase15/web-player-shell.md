# Phase 15 — Web Player Shell / 15.0.0

## Goal

Create the first browser-facing shell for historical playback. This phase does **not** implement real-time live streaming yet and does **not** decode MXF in the browser. It wires the contracts produced in Phases 11–14 into a UI shell that can be used by the future player implementation.

The shell consumes a playback fixture shaped like the Historical Playback API / Segment Export outputs:

- service tree
- selected UTC interval
- playback plan segments
- explicit gaps
- signaling events
- export bundle metadata

## Contract

The UI is service-centric:

```text
Service tree
    ↓
LogicalTrackUUID
    ↓
UTC interval
    ↓
Historical Playback Plan
    ↓
Timeline with media, gaps and events
    ↓
Export / playback actions
```

The Web Player must not rely on physical file names or stable MXF TrackIndex. Those are resolved server-side by the Historical Playback API and Segment Export contracts.

## What this phase includes

- static Web Player shell
- service tree panel
- time interval controls
- timeline visualization with media/gap/event lanes
- segment list
- export manifest panel
- placeholder audio/export action buttons
- local fixture loader
- smoke script that verifies expected UI contract text and fixture shape

## What this phase does not include

- authenticated web server
- live playback
- real MXF demux in browser
- waveform rendering from decoded samples
- user management
- production UX polish

## Gap policy

`gap` blocks are visual and explicit. The shell must never imply that gap silence is recorded evidence. Continuous playback may later insert synthetic silence, but it must remain marked as `not_evidence_audio=true` in manifests.

## Acceptance

The future smoke must prove:

- service tree is present
- interval selection is present
- media, gap and event lanes are represented
- playback plan fixture is valid JSON
- export manifest fixture is valid JSON
- UI can be opened as a static file
- no RX/TX split is introduced as a base model
- services remain mono logical tracks
