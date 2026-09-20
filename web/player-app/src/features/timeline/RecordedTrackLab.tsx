import { useMemo, useState } from 'react'
import { ThemedCheckbox } from '@/components/themed-ui'
import { DEMO_TIMELINE } from '@/features/player/demoTimeline'
import { fromApiTimeline, type TimelineData, type TimelineTrack } from '@/timeline-model'

type SourceMode = 'fixture' | 'real'
type LoadState = 'idle' | 'loading' | 'connected' | 'empty' | 'error'

type RecordedTrack = {
  id: string
  label: string
  group: string
  kind: string
  logicalTrackUUID: string
  segmentCount: number
  durationSeconds: number
  firstUtc: string | null
  lastUtc: string | null
  indexedCount: number
  auditCount: number
}

function summarizeTrack(groupLabel: string, kind: string, track: TimelineTrack): RecordedTrack {
  const segmentCount = track.segments.length
  const durationSeconds = track.segments.reduce(
    (sum, segment) => sum + Math.max(0, (Date.parse(segment.endUtc) - Date.parse(segment.startUtc)) / 1000),
    0,
  )
  const ordered = [...track.segments].sort((a, b) => Date.parse(a.startUtc) - Date.parse(b.startUtc))
  const indexedCount = track.segments.filter(segment => segment.source === 'sqlite_closed_mxf').length
  const auditCount = segmentCount - indexedCount

  return {
    id: track.id,
    label: track.label,
    group: groupLabel,
    kind,
    logicalTrackUUID: track.logicalTrackUUID,
    segmentCount,
    durationSeconds,
    firstUtc: ordered[0]?.startUtc ?? null,
    lastUtc: ordered.at(-1)?.endUtc ?? null,
    indexedCount,
    auditCount,
  }
}

function flattenRecordedTracks(data: TimelineData) {
  return data.groups.flatMap(group =>
    group.tracks
      .filter(track => track.segments.length > 0)
      .map(track => summarizeTrack(group.label, group.kind, track)),
  )
}

function formatDuration(seconds: number) {
  const total = Math.max(0, Math.round(seconds))
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  return h > 0
    ? `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
    : `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
}

function localClock(value: string | null) {
  if (!value) return '—'
  const date = new Date(value)
  return Number.isNaN(date.getTime())
    ? '—'
    : date.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', second: '2-digit' })
}

export function RecordedTrackLab() {
  const [source, setSource] = useState<SourceMode>('fixture')
  const [state, setState] = useState<LoadState>('idle')
  const [data, setData] = useState<TimelineData>(DEMO_TIMELINE)
  const [selectedTrackIds, setSelectedTrackIds] = useState<string[]>(
    flattenRecordedTracks(DEMO_TIMELINE).map(track => track.id),
  )
  const [error, setError] = useState<string | null>(null)
  const [updatedAt, setUpdatedAt] = useState<string | null>(null)

  const tracks = useMemo(() => flattenRecordedTracks(data), [data])
  const selectedCount = tracks.filter(track => selectedTrackIds.includes(track.id)).length

  const applyData = (next: TimelineData, nextSource: SourceMode) => {
    const nextTracks = flattenRecordedTracks(next)
    setData(next)
    setSource(nextSource)
    setSelectedTrackIds(nextTracks.map(track => track.id))
    setState(nextTracks.length > 0 ? 'connected' : 'empty')
    setUpdatedAt(new Date().toLocaleTimeString('pt-BR'))
    setError(null)
  }

  const useFixture = () => applyData(DEMO_TIMELINE, 'fixture')

  const loadReal = async () => {
    setSource('real')
    setState('loading')
    setError(null)

    try {
      const response = await fetch('/api/timeline', { headers: { Accept: 'application/json' } })
      const payload: unknown = await response.json()

      if (!response.ok) {
        const detail = typeof payload === 'object' && payload && 'detail' in payload
          ? String((payload as { detail?: unknown }).detail ?? response.statusText)
          : response.statusText
        throw new Error(detail || `HTTP ${response.status}`)
      }

      applyData(fromApiTimeline(payload as Parameters<typeof fromApiTimeline>[0]), 'real')
    } catch (cause) {
      setState('error')
      setError(cause instanceof Error ? cause.message : 'Falha ao carregar trilhas gravadas.')
      setUpdatedAt(new Date().toLocaleTimeString('pt-BR'))
    }
  }

  const toggleTrack = (trackId: string, checked: boolean) => {
    setSelectedTrackIds(current =>
      checked ? Array.from(new Set([...current, trackId])) : current.filter(id => id !== trackId),
    )
  }

  const selectAll = () => setSelectedTrackIds(tracks.map(track => track.id))
  const clearAll = () => setSelectedTrackIds([])

  return <section className="recorded-track-lab" id="recorded_track_lab">
    <header className="recorded-track-lab-header">
      <div>
        <strong>Recorded Track Lab</strong>
        <small>Valida material persistido por trilha e seleção para futura escuta.</small>
      </div>
      <div className="timeline-data-source-switch" role="group" aria-label="Fonte de trilhas gravadas">
        <button type="button" className={source === 'fixture' ? 'active' : ''} onClick={useFixture}>Fixture</button>
        <button type="button" className={source === 'real' ? 'active' : ''} onClick={loadReal}>Real</button>
        {source === 'real' && <button type="button" onClick={loadReal} disabled={state === 'loading'}>Atualizar</button>}
      </div>
    </header>

    <div className={`recorded-track-status recorded-track-status-${state}`}>
      <span className="recorded-track-status-dot" />
      <div>
        <strong>{source === 'real' ? '/api/timeline' : 'DEMO_TIMELINE'}</strong>
        <small>
          {state === 'loading'
            ? 'carregando trilhas gravadas...'
            : error ?? `${tracks.length} trilhas com material gravado · ${selectedCount} selecionadas para ouvir`}
        </small>
      </div>
      {updatedAt && <time>{updatedAt}</time>}
    </div>

    <div className="recorded-track-toolbar">
      <div>
        <strong>{selectedCount}</strong>
        <span>de {tracks.length} trilhas selecionadas</span>
      </div>
      <div>
        <button type="button" onClick={selectAll} disabled={tracks.length === 0}>Selecionar todas</button>
        <button type="button" onClick={clearAll} disabled={selectedCount === 0}>Limpar seleção</button>
      </div>
    </div>

    <div className="recorded-track-list">
      {tracks.length === 0 ? (
        <div className="recorded-track-empty">
          {state === 'loading' ? 'Consultando material gravado...' : 'Nenhuma trilha gravada encontrada nesta janela.'}
        </div>
      ) : tracks.map(track => {
        const checked = selectedTrackIds.includes(track.id)
        const evidence = track.indexedCount > 0
          ? `${track.indexedCount} indexados${track.auditCount ? ` · ${track.auditCount} audit` : ''}`
          : `${track.auditCount} audit`

        return <article className={`recorded-track-row ${checked ? 'selected' : 'muted'}`} key={track.id}>
          <label className="recorded-track-listen">
            <ThemedCheckbox
              color={checked ? 'blue' : 'gray'}
              checked={checked}
              onCheckedChange={value => toggleTrack(track.id, value === true)}
              aria-label={`${checked ? 'Remover' : 'Adicionar'} ${track.label} da futura escuta`}
            />
            <span>ouvir</span>
          </label>

          <div className="recorded-track-identity">
            <small>{track.kind} · {track.group}</small>
            <strong>{track.label}</strong>
            <code title={track.logicalTrackUUID}>{track.logicalTrackUUID}</code>
          </div>

          <div className="recorded-track-metric">
            <span>segmentos</span>
            <strong>{track.segmentCount}</strong>
          </div>

          <div className="recorded-track-metric">
            <span>gravado</span>
            <strong>{formatDuration(track.durationSeconds)}</strong>
          </div>

          <div className="recorded-track-period">
            <span>{localClock(track.firstUtc)}</span>
            <i>→</i>
            <span>{localClock(track.lastUtc)}</span>
          </div>

          <div className="recorded-track-evidence">
            <span className={track.indexedCount > 0 ? 'indexed' : 'audit'} />
            <strong>{evidence}</strong>
          </div>
        </article>
      })}
    </div>

    <footer className="recorded-track-selection-output">
      <span>selectedTrackIds</span>
      <code>{selectedTrackIds.length ? selectedTrackIds.join(', ') : '[]'}</code>
    </footer>
  </section>
}
