# Frontend Cycle 1 — Real Data Inventory

Date: 2026-09-20

## Frontend construction rule

Every new visual need must pass through the component catalog before it is used in a domain composition or page.

```text
new visual need
    |
    v
already exists in catalog?
    |-- yes -> reuse
    '-- no
         |
         v
base component available?
    |-- yes -> install/use base -> adapt to Audio System theme
    '-- no  -> create project primitive
         |
         v
catalog + isolated visual validation
         |
         v
domain composition
         |
         v
page
```

Pages do not invent visual language. Pages compose previously validated components.

If a shadcn component or another base UI element is needed but is not yet installed, install the base first, wrap/adapt it to the Audio System theme, expose its meaningful variants in the catalog, validate it in isolation, and only then use it in a larger component.

## Cycle 1 goal

Inventory data that already exists in the repository and classify it by how close it is to real frontend consumption.

No complex page is built in this cycle.

## 1. Timeline / historical media — REAL OBSERVED DATA AVAILABLE

This is currently the strongest frontend-real-data boundary.

### Sources

- SQLite temporal index: `runs/index/recorder-index.sqlite`
- Closed operational MXFs under `runs/operational-recorder`
- Recorder audit events
- Logical track identity and track-instance identity
- Historical playback plan contract

### Existing observed timeline builder

`scripts/player/timeline_data.py` already derives UI-facing timeline data from real evidence.

Schema:

```text
recorder-poc.timeline-observed.v1
```

It can expose:

- local date
- local timeline start
- UTC window start/end
- groups
- logical tracks
- media intervals
- indexed/unindexed source provenance
- latest available UTC

Per media segment:

- id
- start_utc
- end_utc
- logical_track_uuid
- track_instance_uuid
- service_type
- service_id
- endpoint_id
- evidence source

### Evidence rules already enforced

Only valid closed media is considered playable evidence.

Indexed path requires:

- `media_interval.state = CLOSED`
- `recording_file.state = CLOSED_COMPLETE`
- referenced MXF exists
- MXF remains under the approved `runs` boundary

Operational fallback requires recorder audit proof including:

- `WINDOW_CLOSED_COMPLETE`
- `MEDIA_COMMIT`
- matching logical/track-instance identity

No silence is fabricated.

### Frontend contract already exists

`web/player-app/src/timeline-model.ts`

Current types:

- `TimelineData`
- `TimelineGroup`
- `TimelineTrack`
- `ActivitySegment`

There is already a translator:

```ts
fromApiTimeline(api)
```

This converts UTC intervals into positions inside the visible timeline window.

### Current limitation

The current frontend model is still built around a fixed 120-minute window:

```text
TOTAL_MINUTES = 120
```

The new ruler/zoom work is moving toward an arbitrary viewport, so this fixed-window assumption should be removed in Cycle 2 before the real multitrack component is composed.

## 2. Historical playback plan — REAL CONTRACT AVAILABLE

`docs/phase13/historical-playback-api.md` defines:

```text
LogicalTrackUUID + UTC interval -> ordered playback plan
```

The plan already distinguishes:

- media
- explicit gaps
- physical file identity
- track instance identity
- track index
- recording window
- segment sequence
- timeline events

Supported conceptual modes:

- continuous
- only_audio
- event_overlay

Future HTTP boundaries are documented for:

- services
- playback plan
- events
- media segment

This is suitable for the future Player, but the documented HTTP service is not yet the browser-facing runtime boundary used by the current catalog.

## 3. Recorder session — REAL DOMAIN CONTRACT AVAILABLE

`contracts/recorder-session.md` defines real recorder behavior.

Available domain facts include:

- RTSP control state
- RTP/PCMA media contract
- recording/ready transitions
- logical track UUID
- track instance UUID
- recording window start UTC
- segment sequence
- session-local RTP ports
- route identity
- file lifecycle
- recording lifecycle
- media counters/evidence concepts

The recorder host can own multiple bounded sessions.

### Frontend status

The current frontend `RecorderConfig` is still demo-oriented:

```text
DEMO_RECORDER
```

Its current fields include:

- name
- ip
- rtspPort
- storageUsedGb
- storageTotalGb
- splitMinutes
- writer
- codec
- streams

There is not yet an equivalent observed browser-facing recorder status contract in the catalog layer.

## 4. SIP gateway — REAL CONFIGURATION EXISTS, FRONTEND MODEL IS STILL DEMO

A concrete gateway configuration exists in:

`config/gateway/sip-ingress.ini`

Real configuration facts include:

- bind IP
- SIP port
- RTP port
- recorder RTSP URI
- recorder RTP port
- gateway ID
- max call duration

Call identity includes:

- endpoint ID
- service type
- service ID
- direction
- call leg ID
- raw SIP call ID
- raw From/To
- ringing time
- answered-media time
- packetization
- payload type

### Frontend status

`web/player-app/src/features/sip/model.ts` currently exposes `DEMO_SIP_GATEWAY`.

The frontend does not yet consume observed gateway state.

## 5. Radio / Telephone / CWP

Observed timeline evidence already carries enough identity to begin rebuilding these entities from real timeline facts:

- `service_type`
- `service_id`
- `endpoint_id`
- `logical_track_uuid`
- `track_instance_uuid`
- media intervals
- provenance

The timeline builder currently derives group kind as CWP/TEL/RADIO from endpoint/service information.

This is sufficient for an initial real-data visual representation of tracks and clips, but not yet a complete operational/configuration model for CWP, Radio or Telephone.

Their previous frontend representations should therefore be treated as reference material only and rebuilt later as compositions of catalog primitives.

## 6. Demo data still present

`web/player-app/src/features/player/demoTimeline.ts` remains useful as deterministic fixture data.

It should not be deleted yet.

Recommended roles:

```text
fixture        -> deterministic visual development
observed data  -> real-data validation
edge fixture   -> empty/error/gap/offline/extreme cases
```

The component itself should not care which source supplied the contract.

## 7. Browser/API gap

The Vite frontend currently has no proxy configuration in `vite.config.ts`.

The repository contains a Python timeline data builder and documented historical playback API shape, but Cycle 1 did not find a current browser-facing HTTP adapter wired into the catalog-only frontend.

Therefore the next data-boundary work should not redesign the UI. It should expose a minimal local gateway/API that translates the existing observed data into stable frontend contracts.

## 8. Source classification

| Domain | Real data exists | Stable domain contract | Browser-facing contract | Current frontend |
| --- | --- | --- | --- | --- |
| Timeline intervals | Yes | Yes | Partial/model exists | Fixture + API translator |
| Historical playback plan | Yes/derivable | Yes | Documented, not yet wired | Not composed |
| Recorder lifecycle/session | Yes | Yes | Not yet catalog-facing | Demo config |
| SIP configuration/call identity | Yes | Partial/strong config | Not yet catalog-facing | Demo config |
| Radio identity/activity | Yes through recorder/index | Partial | Timeline-oriented | Old representation |
| Telephone identity/activity | Yes through SIP/index | Partial | Timeline-oriented | Old representation |
| CWP grouping/activity | Yes through endpoint identity | Partial | Timeline-oriented | Old representation |

## 9. Recommended Cycle 2 boundary

Before rebuilding domain visuals, define frontend DTOs independent of UI:

```text
ObservedTimelineDto
RecorderStatusDto
SipGatewayStatusDto
ServiceTrackDto
MediaIntervalDto
```

Then provide two adapters for each applicable contract:

```text
fixture -> DTO
real API -> DTO
```

The same catalog component must render either source without visual code changes.

## Cycle 1 conclusion

The first real-data visual vertical slice should be:

```text
SQLite / closed MXF evidence
        |
        v
timeline_data / local gateway
        |
        v
ObservedTimelineDto
        |
        v
TimelineRulerZoom
TimelineTrack
TimelineClip
```

This is the shortest existing path from recorder evidence to a visual element and is the best place to prove the new frontend construction method before rebuilding Recorder, SIP, Radio, Telephone and CWP.
