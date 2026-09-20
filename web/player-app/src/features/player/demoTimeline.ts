import type { ActivitySegment, GroupKind, TimelineData, TimelineGroup } from '@/timeline-model'

const START = '2026-09-20T03:00:00.000Z'
const END = '2026-09-20T05:00:00.000Z'

function isoAt(minute: number) {
  return new Date(Date.parse(START) + minute * 60_000).toISOString()
}

function segment(track: string, n: number, start: number, end: number, source: ActivitySegment['source'] = 'sqlite_closed_mxf'): ActivitySegment {
  return {
    id: `${track}-seg-${n}`,
    start,
    end,
    startUtc: isoAt(start),
    endUtc: isoAt(end),
    trackInstanceUUID: `${track}-instance-${Math.floor(start / 30) + 1}`,
    source,
  }
}

function group(id: string, kind: GroupKind, label: string, tracks: Array<[string, string, Array<[number, number, ActivitySegment['source']?]>]>): TimelineGroup {
  return {
    id,
    kind,
    label,
    tracks: tracks.map(([trackId, trackLabel, ranges]) => ({
      id: trackId,
      label: trackLabel,
      logicalTrackUUID: `${trackId}-logical`,
      sources: Array.from(new Set(ranges.map(range => range[2] ?? 'sqlite_closed_mxf'))),
      segments: ranges.map(([start, end, source], index) => segment(trackId, index + 1, start, end, source)),
    })),
  }
}

export const DEMO_TIMELINE: TimelineData = {
  date: '2026-09-20',
  startLocal: '00:00',
  windowStartUtc: START,
  windowEndUtc: END,
  latestAvailableUtc: END,
  groups: [
    group('cwp-a01', 'CWP', 'CWP-001 · Lado A', [
      ['cwp-a01-r1', 'TWR 121.500', [[3, 8], [15, 23], [42, 48], [74, 83], [101, 108]]],
      ['cwp-a01-r2', 'TWR 118.700', [[9, 14], [29, 34], [56, 63], [89, 94]]],
      ['cwp-a01-t1', 'TEL-050', [[18, 27], [68, 72], [96, 103]]],
    ]),
    group('cwp-a02', 'CWP', 'CWP-002 · Lado A', [
      ['cwp-a02-r1', 'APP 125.800', [[5, 11], [36, 41], [61, 69], [110, 116]]],
      ['cwp-a02-r2', 'APP 127.300', [[20, 25], [49, 54], [84, 91]]],
    ]),
    group('cwp-b01', 'CWP', 'CWP-B01 · Lado B', [
      ['cwp-b01-r1', 'GND 121.900', [[7, 12], [31, 38], [79, 87], [105, 112]]],
      ['cwp-b01-r2', 'TWR 121.500', [[24, 29], [52, 58], [92, 99]]],
    ]),
    group('tel-core', 'TEL', 'Telefonia', [
      ['tel-050', 'TEL-050', [[17, 28], [66, 73], [95, 104]]],
      ['tel-060', 'TEL-060', [[38, 46], [86, 93], [114, 118]]],
    ]),
    group('radio-audit', 'RADIO', 'Rádio · audit técnico', [
      ['radio-audit-1', 'Canal legado', [[12, 17, 'closed_mxf_recorder_audit_unindexed'], [58, 62, 'closed_mxf_recorder_audit_unindexed'], [99, 103, 'closed_mxf_recorder_audit_unindexed']]],
    ]),
  ],
  counts: { groups: 5, logical_tracks: 10, media_intervals: 36, indexed_intervals: 33, unindexed_intervals: 3 },
}
