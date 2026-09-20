Phase 3 Recorder Host

01-build-recorder-host.cmd
  Builds the first persistent Windows Recorder executable and runs its runtime/plugin self-test.

02-one-cwp-smoke.cmd
  Deferred integration gate. Starts Recorder Host, drives one logical CWP over RTSP/RTP PCMA, then verifies final MXF, lifecycle, audit events and embedded LT/TI using stock mxfdemux.

The smoke does not need to be run after every implementation change while the rest of the system is being assembled. It belongs to the later integrated acceptance pass.

Phase 4 / Phase 5 additions

03-radio-persistent-session-smoke.cmd
  Deferred Phase 4 gate for one persistent radio session across repeated RECORD/PAUSE cycles.

04-multi-cwp-routing-smoke.cmd
  Deferred Phase 5 gate. Starts one Recorder Host with six preconfigured routes and six concurrent session simulators across five logical CWPs, then validates route/session isolation, packet counts and per-file lifecycle.

05-media-engine-smoke.cmd - future Phase 6 integrated gate for controlled RTP impairments and Media Engine counters.
