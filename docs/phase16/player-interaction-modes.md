# Phase 16 — Player Interaction Modes

## Objective

Phase 16 turns the Phase 15 Web Player shell into an interaction model for historical review. It does not yet perform real backend streaming; it defines and exercises the client-side behavior expected from future playback APIs.

## Frozen model

The player remains based on the Phase 9 service model:

- one recordable service = one mono media flow;
- one service has one `LogicalTrackUUID`;
- physical files and `TrackInstanceUUID`s are resolved by the playback plan;
- explicit gaps remain visible and are not evidence audio.

## Modes

### CONTINUOUS

The timeline keeps the complete requested interval. Gaps are visible. A later audio backend may synthesize silence for presentation, but any synthetic silence must be marked as `not_evidence_audio=true` in the manifest.

### ONLY_AUDIO

The player skips gaps and exposes only recorded media ranges. It must never jump beyond the selected OUT boundary.

### ONLY_ACTIVITY

The player focuses on activity-bearing media. In this PoC shell, activity means a media segment with one or more overlapping signaling events such as `SQU_ON`, `PTT_ON`, `RING`, `ANSWER`, `RELEASE`, `MEDIA_START`, or `MEDIA_END`.

## IN/OUT selection

The user can select a sub-interval inside the playback plan. The UI clips all rendered media, gaps, and events to the IN/OUT selection. Events outside the selected interval are hidden.

## Event overlay

Events are rendered as an overlay on the same timeline as media/gaps. P0/P1/P2/P3 priority is kept as metadata so the full UI can later filter or style events without losing audit semantics.

## Acceptance summary

The Phase 16 smoke validates:

- UI contains mode controls for CONTINUOUS, ONLY_AUDIO and ONLY_ACTIVITY;
- UI exposes IN/OUT fields;
- fixture includes media, gaps and events;
- ONLY_AUDIO calculation excludes explicit gaps;
- ONLY_ACTIVITY calculation keeps activity-bearing media;
- no RX/TX split is reintroduced in the fixture model.
