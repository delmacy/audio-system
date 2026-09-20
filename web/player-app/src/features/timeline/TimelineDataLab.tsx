import { useMemo, useState } from 'react'
import { DataProbe, DataSourceStatus } from '@/primitives'
import { DEMO_TIMELINE } from '@/features/player/demoTimeline'
import { fromApiTimeline, type TimelineData } from '@/timeline-model'

type SourceMode = 'fixture' | 'real'
type LoadState = 'connected' | 'loading' | 'empty' | 'error'

function countSegments(data: TimelineData) {
  return data.groups.reduce(
    (sum, group) => sum + group.tracks.reduce((trackSum, track) => trackSum + track.segments.length, 0),
    0,
  )
}

function countTracks(data: TimelineData) {
  return data.groups.reduce((sum, group) => sum + group.tracks.length, 0)
}

function windowMinutes(data: TimelineData) {
  const start = Date.parse(data.windowStartUtc)
  const end = Date.parse(data.windowEndUtc)
  return Number.isFinite(start) && Number.isFinite(end) && end > start ? (end - start) / 60000 : 1
}

type PreviewWindow = 'full' | '30s' | '10s'

function previewBounds(data: TimelineData, mode: PreviewWindow) {
  const fullStart = Date.parse(data.windowStartUtc)
  const fullEnd = Date.parse(data.windowEndUtc)
  const latest = data.latestAvailableUtc ? Date.parse(data.latestAvailableUtc) : fullEnd
  const end = Number.isFinite(latest) ? Math.min(fullEnd, latest) : fullEnd
  const spanMs = mode === '10s' ? 10_000 : mode === '30s' ? 30_000 : Math.max(1, fullEnd - fullStart)
  const start = mode === 'full' ? fullStart : Math.max(fullStart, end - spanMs)
  return { start, end: mode === 'full' ? fullEnd : end }
}

function formatAxisTime(value: number, includeDate = false) {
  const date = new Date(value)
  return new Intl.DateTimeFormat('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    ...(includeDate ? { day: '2-digit', month: '2-digit' } : {}),
  }).format(date)
}

function TimelineObservedPreview({ data }: { data: TimelineData }) {
  const [windowMode, setWindowMode] = useState<PreviewWindow>('10s')
  const bounds = previewBounds(data, windowMode)
  const durationMs = Math.max(1, bounds.end - bounds.start)
  const tracks = data.groups.flatMap(group =>
    group.tracks
      .map(track => ({ group: group.label, kind: group.kind, track }))
      .filter(({ track }) => track.segments.some(segment => {
        const start = Date.parse(segment.startUtc)
        const end = Date.parse(segment.endUtc)
        return start < bounds.end && end > bounds.start
      }))
  )
  const tickCount = windowMode === '10s' ? 10 : windowMode === '30s' ? 6 : 4
  const ticks = Array.from({ length: tickCount + 1 }, (_, index) =>
    bounds.start + (durationMs * index) / tickCount
  )

  return <div className="timeline-observed-preview" id="timeline_observed_preview">
    <div className="timeline-observed-preview-head">
      <div>
        <strong>UI renderizada</strong>
        <span>{tracks.length} tracks visíveis · {countSegments(data)} clips recebidos</span>
      </div>
      <div className="timeline-observed-window-switch" role="group" aria-label="Janela visual">
        <button type="button" className={windowMode === '10s' ? 'active' : ''} onClick={() => setWindowMode('10s')}>10 s</button>
        <button type="button" className={windowMode === '30s' ? 'active' : ''} onClick={() => setWindowMode('30s')}>30 s</button>
        <button type="button" className={windowMode === 'full' ? 'active' : ''} onClick={() => setWindowMode('full')}>Completa</button>
      </div>
    </div>

    <div className="timeline-observed-axis">
      <div className="timeline-observed-axis-spacer">
        <strong>{windowMode === 'full' ? 'janela' : 'foco recente'}</strong>
        <small>{formatAxisTime(bounds.start)} → {formatAxisTime(bounds.end)}</small>
      </div>
      <div className="timeline-observed-axis-scale">
        {ticks.map((tick, index) => <span key={tick} style={{ left: `${(index / tickCount) * 100}%` }}>
          {formatAxisTime(tick)}
        </span>)}
      </div>
    </div>

    {tracks.length === 0 ? (
      <div className="timeline-observed-empty">Nenhum intervalo de mídia nesta janela.</div>
    ) : (
      <div className="timeline-observed-tracks">
        {tracks.map(({ group, kind, track }) => <div className="timeline-observed-track" key={track.id}>
          <div className="timeline-observed-label">
            <small>{kind} · {group}</small>
            <strong>{track.label}</strong>
          </div>
          <div className="timeline-observed-lane">
            {track.segments.map(segment => {
              const segmentStart = Date.parse(segment.startUtc)
              const segmentEnd = Date.parse(segment.endUtc)
              if (segmentStart >= bounds.end || segmentEnd <= bounds.start) return null
              const clippedStart = Math.max(bounds.start, segmentStart)
              const clippedEnd = Math.min(bounds.end, segmentEnd)
              const left = Math.max(0, Math.min(100, ((clippedStart - bounds.start) / durationMs) * 100))
              const width = Math.max(.55, Math.min(100 - left, ((clippedEnd - clippedStart) / durationMs) * 100))
              return <span
                key={segment.id}
                className={`timeline-observed-clip ${segment.source === 'sqlite_closed_mxf' ? 'indexed' : 'audit'}`}
                style={{ left: `${left}%`, width: `${width}%` }}
                title={`${track.label} · ${segment.startUtc} → ${segment.endUtc} · ${segment.source}`}
              />
            })}
          </div>
        </div>)}
      </div>
    )}
  </div>
}

export function TimelineDataLab() {
  const [source, setSource] = useState<SourceMode>('fixture')
  const [state, setState] = useState<LoadState>('connected')
  const [data, setData] = useState<TimelineData>(DEMO_TIMELINE)
  const [raw, setRaw] = useState<unknown>(DEMO_TIMELINE)
  const [error, setError] = useState<string | null>(null)
  const [updatedAt, setUpdatedAt] = useState<string | null>(null)

  const uiCount = useMemo(() => countSegments(data), [data])
  const trackCount = useMemo(() => countTracks(data), [data])
  const rawCount = raw && typeof raw === 'object' && 'counts' in raw
    ? Number((raw as { counts?: { media_intervals?: number } }).counts?.media_intervals ?? 0)
    : 0
  const dtoCount = uiCount
  const discardedCount = Math.max(0, rawCount - dtoCount)

  const useFixture = () => {
    setSource('fixture')
    setData(DEMO_TIMELINE)
    setRaw(DEMO_TIMELINE)
    setState('connected')
    setError(null)
    setUpdatedAt(new Date().toLocaleTimeString('pt-BR'))
  }

  const loadReal = async () => {
    setSource('real')
    setState('loading')
    setError(null)

    try {
      const response = await fetch('/api/timeline', { headers: { Accept: 'application/json' } })
      const payload: unknown = await response.json()
      setRaw(payload)

      if (!response.ok) {
        const detail = typeof payload === 'object' && payload && 'detail' in payload
          ? String((payload as { detail?: unknown }).detail ?? response.statusText)
          : response.statusText
        throw new Error(detail || `HTTP ${response.status}`)
      }

      const normalized = fromApiTimeline(payload as Parameters<typeof fromApiTimeline>[0])
      setData(normalized)
      setState(normalized.counts.media_intervals > 0 ? 'connected' : 'empty')
      setUpdatedAt(new Date().toLocaleTimeString('pt-BR'))
    } catch (cause) {
      setState('error')
      setError(cause instanceof Error ? cause.message : 'Falha desconhecida ao consultar timeline.')
      setUpdatedAt(new Date().toLocaleTimeString('pt-BR'))
    }
  }

  return <section className="timeline-data-lab" id="timeline_data_lab">
    <header className="timeline-data-lab-header">
      <div>
        <strong>Timeline data lab</strong>
        <small>Confirma recebimento → normalização → renderização real</small>
      </div>
      <div className="timeline-data-source-switch" role="group" aria-label="Fonte de dados">
        <button type="button" className={source === 'fixture' ? 'active' : ''} onClick={useFixture}>Fixture</button>
        <button type="button" className={source === 'real' ? 'active' : ''} onClick={loadReal}>Real</button>
        {source === 'real' && <button type="button" onClick={loadReal} disabled={state === 'loading'}>Atualizar</button>}
      </div>
    </header>

    <DataSourceStatus
      state={state}
      source={source === 'real' ? '/api/timeline' : 'DEMO_TIMELINE'}
      detail={error ?? `${trackCount} tracks · ${data.groups.length} groups`}
      updatedAt={updatedAt}
    />

    <DataProbe
      rawCount={rawCount}
      dtoCount={dtoCount}
      renderedCount={uiCount}
      discardedCount={discardedCount}
    />

    <div className="timeline-data-lab-metrics">
      <div><span>groups</span><strong>{data.groups.length}</strong></div>
      <div><span>tracks</span><strong>{trackCount}</strong></div>
      <div><span>intervals</span><strong>{uiCount}</strong></div>
      <div><span>latest</span><strong>{data.latestAvailableUtc ? new Date(data.latestAvailableUtc).toLocaleTimeString('pt-BR') : '—'}</strong></div>
    </div>

    <TimelineObservedPreview data={data} />

    <details className="timeline-data-raw">
      <summary>Payload observado</summary>
      <pre>{JSON.stringify(raw ?? data, null, 2)}</pre>
    </details>
  </section>
}
