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

export function TimelineDataLab() {
  const [source, setSource] = useState<SourceMode>('fixture')
  const [state, setState] = useState<LoadState>('connected')
  const [data, setData] = useState<TimelineData>(DEMO_TIMELINE)
  const [raw, setRaw] = useState<unknown>(null)
  const [error, setError] = useState<string | null>(null)
  const [updatedAt, setUpdatedAt] = useState<string | null>(null)

  const renderedCount = useMemo(() => countSegments(data), [data])
  const trackCount = useMemo(() => countTracks(data), [data])
  const rawCount = raw && typeof raw === 'object' && 'counts' in raw
    ? Number((raw as { counts?: { media_intervals?: number } }).counts?.media_intervals ?? 0)
    : source === 'fixture'
      ? data.counts.media_intervals
      : 0
  const dtoCount = data.counts.media_intervals
  const discardedCount = Math.max(0, rawCount - renderedCount)

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

  const statusState = state === 'connected' ? 'connected'
    : state === 'loading' ? 'loading'
      : state === 'empty' ? 'empty'
        : 'error'

  return <section className="timeline-data-lab" id="timeline_data_lab">
    <header className="timeline-data-lab-header">
      <div>
        <strong>Timeline data lab</strong>
        <small>Confirma recebimento → normalização → representação</small>
      </div>
      <div className="timeline-data-source-switch" role="group" aria-label="Fonte de dados">
        <button type="button" className={source === 'fixture' ? 'active' : ''} onClick={useFixture}>Fixture</button>
        <button type="button" className={source === 'real' ? 'active' : ''} onClick={loadReal}>Real</button>
        {source === 'real' && <button type="button" onClick={loadReal} disabled={state === 'loading'}>Atualizar</button>}
      </div>
    </header>

    <DataSourceStatus
      state={statusState}
      source={source === 'real' ? '/api/timeline' : 'DEMO_TIMELINE'}
      detail={error ?? `${trackCount} tracks · ${data.groups.length} groups`}
      updatedAt={updatedAt}
    />

    <DataProbe
      rawCount={rawCount}
      dtoCount={dtoCount}
      renderedCount={renderedCount}
      discardedCount={discardedCount}
    />

    <div className="timeline-data-lab-metrics">
      <div><span>groups</span><strong>{data.groups.length}</strong></div>
      <div><span>tracks</span><strong>{trackCount}</strong></div>
      <div><span>intervals</span><strong>{renderedCount}</strong></div>
      <div><span>latest</span><strong>{data.latestAvailableUtc ? new Date(data.latestAvailableUtc).toLocaleTimeString('pt-BR') : '—'}</strong></div>
    </div>

    <details className="timeline-data-raw">
      <summary>Payload observado</summary>
      <pre>{JSON.stringify(raw ?? data, null, 2)}</pre>
    </details>
  </section>
}
