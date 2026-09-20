# AGENTS.md — Recorder PoC / ATM Communications Recording System

## 1. Purpose of this file

This file is the operational memory for future agents, Codex sessions, or maintainers resuming this PoC. It captures the full scope, frozen design decisions, architectural boundaries, evidence rules, phase history, current status, and next implementation backlog.

The project is a Windows-native proof of concept for an air-traffic/ATM-style communications recording system, inspired by ED-137-like recording workflows, but not claiming certified ED-137 compliance. Exact standard conformance, profile attributes, mandatory metadata, and interoperability behavior must be validated against the target standard/profile and real equipment.

This file is intentionally detailed. Do not compress it into a short README unless another file preserves these decisions.

---

## 2. Project objective

Build a native Windows PoC that can simulate and later validate a communications recording architecture with:

- CWP-originated recording sessions using direct RTSP/RTP toward the Recorder.
- SIP/telephony and physical/legacy radio inputs translated by a Recording Gateway into the recording protocol.
- RTP media ingestion using PCMA/G.711 A-law 8 kHz mono.
- MXF storage with stable logical identity and per-file physical track instances.
- SQLite temporal index for historical lookup.
- Web Player shell for historical and live preview paths.
- Evidence export bundle with manifests, source maps, timeline events, gaps, and hashes.
- Observability/event bus that does not block the critical media path.
- Fault injection, stress orchestration, integrated acceptance planning, operator runbook, and release-candidate packaging.

The PoC must distinguish between:

- materialized design/harness artifacts,
- simulated harness outputs,
- live preview buffers,
- real recorded evidence,
- gates not yet executed,
- gates validated in earlier local runs.

A gate that was not executed remains `NOT_RUN` or `BLOCKED`; it must never be reported as `PASS`.

---

## 3. Host and environment constraints

The PoC is intentionally native Windows because the available notebook cannot rely on virtualization or Docker/Hyper-V.

Known target environment:

- Windows host.
- No Docker requirement.
- No Hyper-V/VM requirement.
- GStreamer 1.28.7 MSVC x86_64 runtime/development installation expected under:
  - `C:\Program Files\gstreamer\1.0\msvc_x86_64\bin`
- FFmpeg expected under:
  - `C:\ffmpeg\bin`
- Visual Studio Build Tools 2019 / v142 / MSBuild 16.11 / Windows SDK 10.0.19041 used in the earlier native/plugin work.
- SQLite used as local temporal/index store.
- Wireshark/dumpcap used as independent network/audit witness.

Earlier validated host/network facts from Phase 1/2 work:

- Host label used in notes: `WIN1-SERVER`.
- Lab addresses planned:
  - bind/host: `10.20.0.50`
  - recorder: `10.20.0.10`
  - SIP proxy/gateway: `10.20.0.20`
  - CWP-A range: `10.20.1.101-200`
  - CWP-B range: `10.20.2.101-200`
- Intel I219-LM reserved for possible future external recorder integration.

Treat these as PoC defaults, not production requirements.

---

## 4. Architectural topology

### 4.1 Correct high-level flow

The critical correction is that CWP does not pass through the Recording Gateway.

Correct architecture:

```text
CWP
  -> RTSP/RTP recording protocol directly
  -> Recorder

Telephony SIP
  -> Recording Gateway
  -> RTSP/RTP recording protocol
  -> Recorder

Physical/legacy radio or external protocol adapter
  -> Recording Gateway / adapter
  -> RTSP/RTP recording protocol
  -> Recorder
```

### 4.2 Responsibilities

#### Recorder

The Recorder is responsible for:

- RTSP session handling for recording sessions.
- RTP/RTCP media ingest.
- MXF writer pipeline.
- file lifecycle, `.partial` files, `.lock` sidecars, close/promote semantics.
- LogicalTrackUUID/TrackInstanceUUID association.
- topology/window rotation.
- emitting events to observability/index/export subsystems.
- not blocking media ingestion on logs, SQLite, player, or metrics exporters.

#### Recording Gateway

The Gateway is responsible for protocol translation only:

- SIP/telephony ingress -> RTSP/RTP recording session.
- physical/legacy radio/external adapter -> RTSP/RTP recording session.
- call/ring/answer/release lifecycle events mapped to recorder events.

The Gateway is not used for CWP direct protocol.

#### Media Bank / Media Engine

The Media Bank/Engine is responsible for:

- collecting or generating radio/telephony clips.
- converting to PCMA/G.711 A-law 8 kHz mono.
- classifying folders by simulation role when useful, e.g. controller/pilot, telephone tones, conversation clips.
- not defining Recorder track model. Folder roles are simulator metadata only.

#### Web Player

The Web Player has separate paths:

- Historical/evidential playback: uses SQLite temporal index and playback/export APIs.
- Live/operational preview: uses a live tap/buffer; does not read partial MXF files and is not evidence.

---

## 5. Frozen audio and track model

The base model is:

In words: one mono media flow per logical service, frequency, or call leg.

```text
1 logical service/frequency/call leg
= 1 RTP/UDP mono media flow
= 1 LogicalTrackUUID
= 1 MXF audio track per physical file occurrence
```

Do not reintroduce RX/TX as separate Recorder/MXF tracks in the base model.

Allowed use of RX/TX-like labels:

- media-bank folder semantics,
- simulation speaker roles,
- event/timeline metadata,
- human display labels.

Not allowed by default:

- RX track + TX track for the same logical service in MXF.
- separate LogicalTrackUUIDs for controller and pilot merely because they speak at different moments on one radio frequency.

If future real equipment delivers independent physical media flows, treat that as an explicit integration exception, not the base model.

SQU/PTT/RING/ANSWER/RELEASE and similar state changes are timeline events, not audio channels.

---

## 6. Identity model

### 6.1 LogicalTrackUUID

`LogicalTrackUUID` is the stable application identity of a logical service/media flow.

It is deterministic, derived from a versioned canonical semantic identity, conceptually UUIDv5-like.

Examples:

```text
identity-v1|service_type=radio|service_id=121500|endpoint_id=cwp-a17|media_flow=mono
identity-v1|service_type=telephone|service_id=tel-01|endpoint_id=gateway-sip-01|media_flow=mono|call_leg_id=leg-poc-0001
```

Radio/service identity may remain stable across files, topology changes, and track-index relocation.

Telephone identity must include a call leg/session component when simultaneous calls on the same endpoint/service could otherwise collapse into one logical identity.

### 6.2 TrackInstanceUUID

`TrackInstanceUUID` identifies one physical occurrence of a logical track in a specific MXF/file fragment/window/part.

Rules:

- new file/window/part -> new TrackInstanceUUID;
- same LogicalTrackUUID can appear with many TrackInstanceUUIDs;
- TrackInstanceUUID must be unique for the physical occurrence.

### 6.3 TrackIndex

`TrackIndex` is file-local and physical. It may change freely from file to file.

Never use TrackIndex as stable business identity.

### 6.4 MXF fields

Do not overload native MXF TrackID/TrackNumber with application identity.

The custom MXF identity plugin work embeds semantic identity in MXF TrackName while preserving native MXF structural semantics.

TrackName format:

```text
<DisplayName> | LT=<LogicalTrackUUID> | TI=<TrackInstanceUUID>
```

Preserve raw SDP/service metadata where available:

- `SdpServiceNameRaw`
- `SdpLabelRaw`
- `SdpMidRaw`

Relevant SDP attributes for future profile validation include RFC 5888 `a=mid` and RFC 4574 `a=label`, but exact target profile rules remain to be verified.

---

## 7. Protocol assumptions and RTSP lifecycle

Operational edge protocols include:

- SIP + SDP + RTP/RTCP for telephony/gateway input.
- RTSP + RTP/RTCP for the recording core.

Typical recorder session lifecycle used in the PoC:

```text
OPTIONS
ANNOUNCE / SDP / metadata when needed
SETUP
RECORD
RTP / RTCP
PAUSE
GET_PARAMETER keepalive
RECORD
RTP / RTCP
TEARDOWN
```

Frequency enabled / radio service open may keep an RTSP session open during silence. RECORD/PAUSE represents active media windows or activity, while TEARDOWN represents disable/end of the session.

Open session does not mean active media.

---

## 8. Topology and window/file policy

Supported topology change policies:

```ini
[topology]
change_policy = immediate
boundary_minutes = 60
force_immediate_for_required_new_media = true
logical_track_identity_version = 1
```

Modes:

- `immediate`: topology update closes current part and opens a new physical MXF with the new track matrix.
- `next_boundary`: admin changes are staged until the next boundary, usually next hour/file window.

Safety override:

- A required newly introduced media source that cannot fit the current MXF forces immediate rollover.
- Configuration cannot authorize silent media loss.

Important events:

- `TOPOLOGY_CHANGE`
- `TRACK_ADDED`
- `TRACK_REMOVED`
- `TRACK_RELOCATED`
- `TRACK_RENAMED`
- `FILE_ROLLOVER`

`TRACK_RELOCATED` means same LogicalTrackUUID, different TrackIndex in a later file.

Player and export must hide physical rollover details unless requested for evidence/source-map inspection.

---

## 9. File lifecycle and File Manager policy

Files use an in-progress/final lifecycle:

- `.mxf.partial` while being written.
- `.mxf.lock` sidecar while owned by an active writer.
- final `.mxf` only after clean finalize/promote.

Simplified lifecycle:

```text
ALLOCATED
-> RECORDING_LOCKED
-> FINALIZING
-> CLOSED_COMPLETE
```

Crash or stale-lock recovery may produce states such as:

- `RECOVERED_INCOMPLETE`
- `CORRUPTED`
- `GAP`

Pre-arm requirement:

- Do not create files at T0 boundary.
- Pre-create next-window files before T0.
- Open handles, create locks, prepare metadata, and leave writers ARMED.
- At T0 only perform routing/activation to already prepared writers.

Validated default from File Manager Phase 2:

```ini
[file_manager]
precreate_lead_ms = 3000
ready_deadline_ms_before_window = 250
required_ready_ratio = 1.0
activation_budget_ms = 250
```

If not all files are ready before the boundary, do not silently create late at T0. Use a `BOUNDARY_SPILL_REQUIRED` style behavior, continue prior writer when possible, and report actual rollover/spill timing.

---

## 10. Durability and recovery notes

Durability was designed but not fully validated in the same way as the File Manager pre-arm gates.

Important watermarks:

- `LAST_RECEIVED`
- `LAST_WRITTEN`
- `LAST_DURABLE`
- `LAST_RECOVERABLE`

Target principle:

- RPO initially around <= 1 second, subject to later experimental validation.
- Warn if durability lag exceeds configured threshold.
- Critical if lag is high or evidence state becomes ambiguous.

Important distinction:

```text
Durable bytes != structurally recoverable MXF
```

Future implementation must establish empirically whether `LAST_RECOVERABLE ≈ LAST_DURABLE` or whether additional sidecar/journal/footer reconstruction is needed.

---

## 11. SQLite temporal index model

SQLite is the temporal lookup/index layer. It must be rebuildable from authoritative recording artifacts where possible.

Core concepts:

- `logical_track`
- `recording_file`
- `track_instance`
- `media_interval`
- `recording_event`
- `ingestion_checkpoint`

Canonical query:

```text
LogicalTrackUUID + [from_utc, to_utc)
```

returns ordered physical segments:

- FileId
- TrackInstanceUUID
- TrackIndex
- physical relative path
- valid_from / valid_to
- RecordingWindowStartUTC
- SegmentSequence

Rules:

- UTC internally.
- gaps are explicit; never fabricate unknown media.
- historical closed MXFs are immutable.
- TrackIndex is only a file-local selector.
- ordering is by RecordingWindowStartUTC + SegmentSequence, not file creation time.

SQLite failure must not stop critical Recorder media ingestion. Indexer lag must be observable.

---

## 12. Playback and Web Player model

### 12.1 Historical path

Historical path:

```text
SQLite Temporal Index
-> Historical Playback API
-> Playback Plan
-> Segment Export / Decode
-> Web Player / Export
```

A playback plan resolves logical queries into physical material:

- FileId
- MXF path
- TrackInstanceUUID
- TrackIndex
- intervals
- gaps
- events

### 12.2 Player modes

Modes:

- `CONTINUOUS`: preserve interval duration and display gaps explicitly; may insert synthetic silence only for presentation.
- `ONLY_AUDIO`: remove gaps from playback sequence but retain gap information in manifest/timeline.
- `ONLY_ACTIVITY`: focus on media associated with activity/signal events.

Rules:

```text
synthetic silence != evidence
explicit gap != recorded audio
```

### 12.3 Live path

Live path:

```text
Recorder Live Tap
-> Live Player Buffer
-> Web Player
```

Rules:

- Live player does not read `.mxf.partial`.
- Live buffer is operational preview only.
- Live buffer is not evidence.
- Evidence comes from closed MXF + manifest + index + hashes.

---

## 13. Evidence export and integrity chain

Evidence export bundle concept:

```text
Export Evidence Bundle
├── audio/export.wav
├── manifest/export-manifest.json
├── manifest/source-map.csv
├── manifest/timeline-events.jsonl
├── manifest/gaps.jsonl
├── hashes/file-hashes.sha256
├── hashes/package-hash.txt
└── README-EVIDENCE.txt
```

Evidence chain:

```text
MXF closed
-> recording-file-manifest.json
-> SQLite Temporal Index
-> Historical Playback Plan
-> Segment Export
-> Evidence Bundle
-> Integrity Verification Report
```

Must preserve and cross-check:

- FileId
- LogicalTrackUUID
- TrackInstanceUUID
- TrackIndex
- RecordingWindowStartUTC
- SegmentSequence
- MXF hash
- manifest hash
- source-map hash
- export audio hash
- bundle hash

Critical rules:

```text
Live buffer is not evidence.
Synthetic silence is not evidence.
Fixture data is not evidence.
Harness simulation is not recorded evidence.
Gap is not fabricated audio.
```

---

## 14. Observability and event bus

The Event Bus is asynchronous and must not block critical RTP/media/write path.

Priority classes:

- P0: critical evidence/integrity/session/gap events. Never silently drop.
- P1: operational signaling/session lifecycle. Preserve preferentially; spill if needed.
- P2: aggregated metrics/telemetry. Can be coalesced.
- P3: debug/trace. Dropped first under pressure.

Examples:

```text
P0: CONNECTION_LOST, GAP_START, GAP_END, SESSION_OPEN, SESSION_CLOSE, INTEGRITY_FAILURE, TOPOLOGY_CHANGE
P1: SQU_ON/OFF, PTT_ON/OFF, RING, ANSWER, RELEASE, RECONNECTED
P2: packets/s, bytes/s, queue depth, indexer lag, writer stats
P3: parser traces, verbose diagnostics
```

Observability self-health events:

- `OBSERVABILITY_SINK_DEGRADED`
- `OBSERVABILITY_SINK_RECOVERED`
- `OBSERVABILITY_QUEUE_PRESSURE`
- `OBSERVABILITY_P1_SPILL_STARTED`
- `OBSERVABILITY_P1_SPILL_DRAINED`
- `OBSERVABILITY_INTEGRITY_FAILURE`

Metrics cardinality policy:

Allowed labels are bounded labels such as:

- service_id
- endpoint_id
- session_slot
- priority
- sink

Do not use unbounded IDs as Prometheus labels:

- FileId
- TrackInstanceUUID
- CallId
- RTP sequence number

Put high-cardinality evidence identifiers in logs/manifests/source maps, not metric labels.

---

## 15. Fault, stress, acceptance, and runbook posture

Fault behavior principles:

- Injected or real faults may produce explicit gaps, degraded states, incomplete recovery, or retry status.
- They must not produce silent loss, cross-service contamination, or false evidence.

Failure classification vocabulary:

- `PASS`
- `PASS_WITH_WARNINGS`
- `DEGRADED_EXPECTED`
- `FAIL_INTEGRITY`
- `FAIL_CROSS_CONTAMINATION`
- `FAIL_SILENT_LOSS`
- `FAIL_RUNNER_ERROR`

Stress levels planned:

- L1: 1 service
- L2: 5 services
- L3: 10 services
- L4: 30 services
- L5: 50 services
- L6: 100 services optional/capacity challenge

Integrated acceptance critical failures include:

- silent media loss,
- service cross-contamination,
- P0 silently dropped,
- LogicalTrackUUID mismatch,
- TrackInstanceUUID/source-map mismatch,
- unreported gap,
- bundle hash mismatch,
- manifest chain mismatch,
- live buffer treated as evidence,
- synthetic silence treated as recorded audio.

Runbook rule:

```text
NOT_RUN remains NOT_RUN.
NOT_RUN never becomes PASS.
```

---

## 16. Phase history and status

### Phase 1 — Network foundation

Status: COMPLETE / VALIDATED.

- Native Windows network baseline.
- Loopback/lab network preparation.
- dumpcap/Wireshark independent witness.

### Phase 2 — MXF + Identity + File Manager

Status: COMPLETE / VALIDATED for several key gates.

Highlights:

- GStreamer MXF experiments.
- 100/500/1000-track synthetic/materialization tests.
- custom MXF identity plugin (`mxfidmux`).
- embedded TrackName/LT/TI identity recovery with stock demux.
- cross-file LogicalTrackUUID continuity.
- File Manager pre-arm capacity and loaded pre-arm tests.

Validated scale observations:

- 1000-track preencoded PCMA matrix materialized.
- 1000 active around 42.59 MB file size in that test.
- This proves cardinality/offline-ish appsrc path, not final 1000 continuous real-time ingest.

### Phase 3 — Minimal Recorder + One CWP

Status: MATERIALIZED.

- `recorder-host.exe` concept.
- StorageWriter with own handle, `.mxf.partial`, `.mxf.lock`.
- RTSP/RTP one-CWP smoke harness.

### Phase 4 — Radio Persistent RTSP Session

Status: MATERIALIZED.

- persistent radio session with multiple RECORD/PAUSE bursts.
- same session/file until TEARDOWN/frequency disable.

### Phase 5 — Multi Session Engine

Status: MATERIALIZED.

- SessionManager, multiple RTSP clients/sessions, RTP routing.
- isolated teardown.

### Phase 6 — Media Engine RTP Protection

Status: MATERIALIZED.

- malformed/wrong PT/duplicate/out-of-order/gap/timestamp discontinuity classification.
- audit events for dropped/invalid RTP.

### Phase 7 — Window Rotation Real

Status: MATERIALIZED.

- stable LogicalTrackUUID across rotation.
- new TrackInstanceUUID per window/file.
- same session route across file rollover.

### Phase 8 — Recording Gateway / SIP Ingress

Status: MATERIALIZED.

- SIP/telephony lifecycle translated to recorder RTSP/RTP.
- later correction preserved: gateway is not for CWP direct path.

### Phase 9 — Service Perspective MXF Matrix

Status: MATERIALIZED.

- corrected mono service perspective.
- one service/flow/LT/track.
- no RX/TX base split.

### Phase 10 — Media Bank + Conversation Generator

Status: MATERIALIZED / FROZEN.

- media-bank folder structure.
- silence detection/cut manifest scripts.
- conversation scenario generation.
- future improvements postponed/frozen.

### Audio sample analysis side artifact

- source: aviation controller/pilot public-style clip uploaded by user.
- 47 meaningful clips extracted after silence segmentation.
- classified into controller/pilot/unknown folders.
- WAV 8 kHz mono output and manifests.

### Phase 11 — SQLite Temporal Index

Status: MATERIALIZED.

- schema and query contract.
- LT + interval -> physical FileId/TI/TrackIndex segments.

### Phase 12 — Event Bus + Observability

Status: MATERIALIZED.

- async event bus contract.
- P0/P1/P2/P3 policies.
- metrics contract and cardinality rules.

### Phase 13 — Historical Playback API

Status: MATERIALIZED.

- Playback plan resolution from temporal index.
- explicit gaps and physical segment mapping.

### Phase 14 — Playback Decode / Segment Export

Status: MATERIALIZED.

- export contract from playback plan.
- WAV/manifest/source-map/events bundle skeleton.
- real MXF decode still future implementation.

### Phase 15 — Web Player Shell

Status: MATERIALIZED.

- web/player shell.
- service tree, timeline, media/gaps/events display.

### Phase 16 — Player Interaction Modes

Status: MATERIALIZED.

- CONTINUOUS, ONLY_AUDIO, ONLY_ACTIVITY.
- IN/OUT selection.
- event overlays.

### Phase 17 — Live Player Branch

Status: MATERIALIZED.

- live path separated from historical evidence path.
- live buffer not evidence.

### Phase 18 — Export Evidence Bundle

Status: MATERIALIZED.

- evidence bundle structure.
- hashes and manifest/source-map files.

### Phase 19 — Integrity / Manifest Chain

Status: MATERIALIZED.

- chain from MXF manifest to export bundle.
- integrity smoke harness.

### Phase 20 — Fault Injection / Recovery Harness

Status: MATERIALIZED.

- RTP loss/duplicate/out-of-order.
- session drop/recovery.
- indexer restart.
- observability degradation.
- export retry.
- partial file recovery.

### Phase 21 — Progressive Stress / Scenario Runner

Status: MATERIALIZED.

- progressive levels L1-L6.
- round reporting and classification.

### Phase 22 — Integrated Acceptance Plan

Status: MATERIALIZED.

- consolidated acceptance campaign.
- `NOT_RUN` stays blocked/not pass.

### Phase 23 — Operator Runbook / Deployment Notes

Status: MATERIALIZED.

- Windows PoC run order.
- prerequisites, commands, troubleshooting.

### Phase 24 — Final PoC Packaging / Release Candidate

Status: MATERIALIZED.

- release candidate packaging.
- RC status vocabulary: RC_PACKAGED, RC_READY_FOR_EXECUTION, RC_BLOCKED, RC_VALIDATED.

### Phase 25 — Closure / Open Risks / Next Implementation Backlog

Status: MATERIALIZED.

- this AGENTS.md/CODEX handoff.
- open risks.
- next implementation backlog.
- closure boundary between materialized PoC and executable/validated system.

---

## 17. Current project state

The PoC is extensively materialized as documentation, scripts, configs, fixtures, smoke harnesses, and native-source stubs.

The following are not the same:

- Materialized: files/scripts/docs exist and encode the intended contract.
- Executed: a script/gate was actually run on the target host.
- Validated: gate executed and produced passing evidence.
- Operational: service can run long duration under real load with recovery and evidence guarantees.

At closure, many phases after Phase 2 are materialized but not necessarily executed on the target Windows host in this conversation.

Do not overclaim readiness.

---

## 18. Open risks

### 18.1 Real MXF decode/export

Phase 14 currently defines export contract and deterministic harness behavior. The final implementation must actually demux/decode the selected MXF track by TrackInstanceUUID/TrackIndex and produce verified output.

Risk: if MXF metadata mapping is incomplete, export may select the wrong physical track.

Mitigation: always verify LT/TI/TrackIndex from embedded MXF metadata, manifest, and SQLite source map.

### 18.2 Continuous real-time scale

The PoC demonstrated large cardinality in synthetic/preencoded tests, but not full continuous real-time ingest at maximum target scale.

Risk: CPU, disk I/O, queueing, and memory behavior under long run may differ.

Mitigation: run progressive stress Phase 21, then integrated acceptance Phase 22.

### 18.3 Durability/recovery exact RPO

Durability watermarks are designed but not fully proven.

Risk: bytes may be durable but not structurally recoverable as MXF.

Mitigation: implement recovery experiments and compare LAST_DURABLE vs LAST_RECOVERABLE.

### 18.4 ED-137/profile conformance

The PoC is inspired by ED-137-style flows but does not certify profile compliance.

Risk: target recorder/profile may require specific SDP attributes, metadata, timing, RTSP behavior, or MXF metadata.

Mitigation: validate against official target profile and real equipment/interoperability tests.

### 18.5 Windows file locking and antivirus interference

Windows handle sharing/rename/delete semantics matter. Antivirus or indexing tools can interfere.

Risk: lock/rename/finalize failures.

Mitigation: controlled recording directories, exclusion policies, File Manager lock probes, stale recovery.

### 18.6 Observability under backpressure

Event bus must not block media path, but P0 must not be silently dropped.

Risk: sink outage causes P0 pressure and unclear operational behavior.

Mitigation: spill/journal strategy and explicit `OBSERVABILITY_INTEGRITY_FAILURE`.

### 18.7 Live preview misinterpretation

Users may mistake live buffer or fixture output for evidence.

Risk: investigative misuse.

Mitigation: UI labels, export policies, runbook, evidence bundle hashes.

---

## 19. Next implementation backlog

### Priority A — make materialized gates executable end-to-end

1. Run Phase 23 runbook smoke.
2. Run Phase 24 packaging smoke.
3. Run Phase 22 integrated acceptance in simulated mode only to validate aggregation.
4. Fix missing paths/scripts discovered by the runbook/package gates.
5. Record each run under `runs/<phase>/<run-id>/` with machine-readable reports.

### Priority B — implement real Historical Decode

1. Use GStreamer/FFmpeg to demux MXF.
2. Resolve correct track by embedded TrackName LT/TI and/or TrackIndex.
3. Extract interval from selected physical segment.
4. Produce WAV/PCMA output and source map.
5. Verify output hash chain.

### Priority C — run actual Recorder smoke gates

1. Build recorder host.
2. Run one-CWP RTSP/RTP smoke.
3. Run radio persistent session smoke.
4. Run multi-CWP routing smoke.
5. Run Media Engine RTP protection smoke.
6. Run window rotation smoke.
7. Run service perspective matrix smoke.

### Priority D — index/playback/export chain

1. Initialize SQLite temporal index.
2. Ingest generated manifests/events.
3. Query playback plan.
4. Export segment bundle.
5. Verify integrity chain.
6. Open in Web Player fixture/live shell.

### Priority E — fault and stress campaigns

1. Run fault injection smoke.
2. Run progressive stress L1-L3.
3. Stabilize runner output.
4. Run L4-L5.
5. Treat L6 as capacity challenge, not minimum acceptance.

### Priority F — conformance and external interoperability

1. Obtain target ED-137/profile requirements.
2. Compare RTSP sequence, SDP attributes, metadata, RTP payload behavior.
3. Validate with target recorder/equipment where possible.
4. Add profile-specific adapters without corrupting the model-base.

---

## 20. Coding and agent rules

Future agents must follow these rules:

1. Preserve CWP direct path. Do not route CWP through Gateway.
2. Preserve mono service model. Do not reintroduce RX/TX tracks as default.
3. Do not use TrackIndex as stable identity.
4. Do not treat live buffer as evidence.
5. Do not treat synthetic silence as evidence.
6. Do not convert `NOT_RUN` into `PASS`.
7. Do not block media path on SQLite, logs, metrics, player, or export.
8. Do not drop P0 silently.
9. Do not claim ED-137 compliance until verified against target profile/equipment.
10. Prefer Windows-native scripts and commands.
11. Use `patch` for normal evolution; reserve `hotfix` for actual defect correction.
12. Keep output artifacts under versioned phase/package names.
13. Update this file when a decision becomes frozen or a phase materially changes.

---

## 21. Naming convention

Use:

- `phaseXX-YY.0.0` for phase packages.
- `patch` for normal incremental delivery.
- `release candidate` for consolidated package state.
- `hotfix` only for genuine defect correction.

Legacy files with `HOTFIX` in their names exist from earlier phases. Do not rename historical artifacts unless the package policy explicitly includes a migration.

---

## 22. Quick command map

Representative gates:

```powershell
.\scripts\network\04-smoke-test.cmd
.\scripts\mxf\19-file-manager-loaded-prearm.cmd
.\scripts\recorder\02-one-cwp-smoke.cmd
.\scripts\recorder\03-radio-persistent-session-smoke.cmd
.\scripts\recorder\04-multi-cwp-routing-smoke.cmd
.\scripts\recorder\05-media-engine-smoke.cmd
.\scripts\recorder\06-window-rotation-smoke.cmd
.\scripts\recorder\07-recording-gateway-smoke.cmd
.\scripts\recorder\08-service-perspective-matrix-smoke.cmd
.\scripts\indexer\09-temporal-index-smoke.cmd
.\scripts\observability\10-observability-event-bus-smoke.cmd
.\scripts\playback\11-historical-playback-smoke.cmd
.\scripts\playback\12-playback-segment-export-smoke.cmd
.\scripts\player\13-web-player-shell-smoke.cmd
.\scripts\player\14-player-interaction-modes-smoke.cmd
.\scripts\player\15-live-player-branch-smoke.cmd
.\scripts\export\16-export-evidence-bundle-smoke.cmd
.\scripts\integrity\17-integrity-manifest-chain-smoke.cmd
.\scripts\fault\18-fault-injection-recovery-smoke.cmd
.\scripts\stress\19-progressive-stress-smoke.cmd
.\scripts\acceptance\20-integrated-acceptance-plan-smoke.cmd
.\scripts\runbook\21-operator-runbook-smoke.cmd
.\scripts\release\22-final-poc-packaging-smoke.cmd
.\scripts\closure\23-closure-backlog-smoke.cmd
```

Run only on the target Windows environment unless the script is explicitly a static/materialization smoke compatible with the current shell.

---

## 23. Closure statement

As of Phase 25, the project has a broad, internally consistent PoC architecture and a phased artifact set from network preparation through release-candidate packaging and closure/backlog documentation.

The next real value step is not adding more conceptual phases; it is executing the runbook on the Windows host, repairing any path/build defects, implementing real historical MXF decode/export, and running the integrated acceptance campaign honestly.

---

## 24. RC1 Windows execution update — 2026-09-19

The first RC1 execution is recorded in `runs/rc1/rc1-20260919-134242/RC1-execution-report.md` with per-command invocation and output files. Its current status is `RC_BLOCKED`; integrated acceptance has 12 of 19 required gates passing in their measured scope.

Closed MXFs were ingested into SQLite, queried by LogicalTrackUUID, decoded by selected physical track with FFmpeg, and packaged with verified source-map and hashes. Recorder media audit now carries cumulative recorded payload byte offsets for exact full-interval extraction. Two PCMA tones (2500 Hz and 3500 Hz) were sent on distinct direct CWP routes and confirmed in the respective closed MXF tracks with embedded LT/TI verification.

Remaining work is Recorder-generated recording-file manifests, arbitrary interval clipping, real Player historical/live integration, observability sink/P0 pressure behavior, recovery fault cases, mixed Gateway/CWP and sustained stress, and target profile interoperability. Existing static or fixture PASS results do not satisfy these real integration gates. See the RC1 report for exact evidence and `NOT_RUN` cases.

## 25. Local systems launch — 2026-09-19

`scripts/recorder/Start-RecorderLab.ps1` can arm a one-service direct CWP RTSP/RTP Recorder process. `scripts/player/Start-WebPlayer.ps1` starts a localhost historical Player backed by the latest executed SQLite index and real closed-MXF segment export. The initial live browser run is recorded in `runs/operational-stack/current-launch-report.json`; operating details are in `docs/rc1/operational-launch.md`. These are partial operational capabilities. Gateway daemon, continuous indexer, Recorder live tap and authoritative file-manifest chain remain open. An armed `.mxf.partial` is never evidence.
