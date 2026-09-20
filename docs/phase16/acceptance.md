# Phase 16 Acceptance

## Static acceptance

- `web/player/index.html` includes playback mode controls.
- `web/player/assets/player.js` contains implementations for `continuous`, `only_audio`, and `only_activity` modes.
- `web/player/assets/player.js` clips media, gaps and events by IN/OUT.
- `web/player/fixtures/playback-plan.sample.json` remains service-mono oriented.
- The base fixture does not introduce `RX`, `TX`, stereo, or dual-channel tracks.

## Future integrated acceptance

When connected to the Historical Playback API and Segment Export API:

- CONTINUOUS playback must retain selected time context and show explicit gaps.
- ONLY_AUDIO playback must skip gaps without crossing OUT.
- ONLY_ACTIVITY playback must focus on media associated with signaling/activity.
- Event overlay must align with the selected interval.
- Export mode must record whether silence was synthetic or recorded.
