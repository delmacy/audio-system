export type GroupKind = 'CWP' | 'TEL' | 'RADIO'

export type ActivitySegment = {
  id: string
  start: number
  end: number
  startUtc: string
  endUtc: string
  trackInstanceUUID: string
  source: 'sqlite_closed_mxf' | 'closed_mxf_recorder_audit_unindexed'
}

export type TimelineTrack = {
  id: string
  label: string
  logicalTrackUUID: string
  segments: ActivitySegment[]
  sources: string[]
}

export type TimelineGroup = {
  id: string
  kind: GroupKind
  label: string
  tracks: TimelineTrack[]
}

export type TimelineData = {
  date: string
  startLocal: string
  windowStartUtc: string
  windowEndUtc: string
  groups: TimelineGroup[]
  counts: { groups: number; logical_tracks: number; media_intervals: number; indexed_intervals: number; unindexed_intervals: number }
  latestAvailableUtc: string | null
}

type ApiSegment = { id: string; start_utc: string; end_utc: string; track_instance_uuid: string; source: ActivitySegment['source'] }
type ApiTrack = { id: string; label: string; logicalTrackUUID: string; segments: ApiSegment[]; sources: string[] }
type ApiGroup = { id: string; kind: GroupKind; label: string; tracks: ApiTrack[] }
type ApiTimeline = {
  schema: string; date: string; start_local: string; window_start_utc: string; window_end_utc: string
  groups: ApiGroup[]; counts: TimelineData['counts']; latest_available_utc: string | null
}

export const TOTAL_MINUTES = 120

export function fromApiTimeline(api: ApiTimeline): TimelineData {
  if (api.schema !== 'recorder-poc.timeline-observed.v1') throw new Error('Resposta de timeline incompatível.')
  const origin = Date.parse(api.window_start_utc)
  const windowEnd = Date.parse(api.window_end_utc)
  if (!Number.isFinite(origin) || !Number.isFinite(windowEnd) || windowEnd <= origin) {
    throw new Error('Janela temporal da timeline inválida.')
  }
  const windowMinutes = (windowEnd - origin) / 60000
  return {
    date: api.date, startLocal: api.start_local, windowStartUtc: api.window_start_utc,
    windowEndUtc: api.window_end_utc, counts: api.counts, latestAvailableUtc: api.latest_available_utc,
    groups: api.groups.map(group => ({ ...group, tracks: group.tracks.map(track => ({ ...track,
      segments: track.segments.map(segment => ({
        id: segment.id, startUtc: segment.start_utc, endUtc: segment.end_utc,
        trackInstanceUUID: segment.track_instance_uuid, source: segment.source,
        start: Math.max(0, Math.min(windowMinutes, (Date.parse(segment.start_utc) - origin) / 60000)),
        end: Math.max(0, Math.min(windowMinutes, (Date.parse(segment.end_utc) - origin) / 60000)),
      })).filter(segment => segment.end > segment.start),
    })) })),
  }
}

export function clampMinute(value: number): number {
  return Math.max(0, Math.min(TOTAL_MINUTES, value))
}

export function formatClock(minute: number, windowStartUtc: string, seconds = false): string {
  const date = new Date(Date.parse(windowStartUtc) + Math.round(clampMinute(minute) * 60000))
  return new Intl.DateTimeFormat('pt-BR', { timeZone: 'America/Sao_Paulo', hour: '2-digit', minute: '2-digit',
    ...(seconds ? { second: '2-digit' } : {}), hour12: false }).format(date)
}

export function formatDuration(minutes: number): string {
  const total = Math.max(0, Math.round(minutes * 60))
  return String(Math.floor(total / 3600)).padStart(2, '0') + ':' +
    String(Math.floor((total % 3600) / 60)).padStart(2, '0') + ':' +
    String(total % 60).padStart(2, '0')
}
