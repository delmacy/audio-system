import { useEffect, useMemo, useRef, useState, type PointerEvent as ReactPointerEvent } from 'react'
import { CalendarDays, ChevronDown, ChevronLeft, MoreHorizontal, Pause, Play, RotateCcw, RotateCw, SkipBack, SkipForward, Volume2, ZoomIn, ZoomOut } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Checkbox } from '@/components/ui/checkbox'
import { Collapsible, CollapsibleContent } from '@/components/ui/collapsible'
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { Slider } from '@/components/ui/slider'
import { TOTAL_MINUTES, clampMinute, formatClock, formatDuration, fromApiTimeline, type GroupKind, type TimelineData, type TimelineGroup, type TimelineTrack } from '@/timeline-model'
import { useTimelineStore } from '@/timeline-store'

const LABEL_WIDTH = 220
const AXIS_MIN_WIDTH = 900
type DragMode = 'start' | 'end' | 'move' | 'playhead' | 'create'
type DragState = {
  mode: DragMode
  originX: number
  originMinute: number
  start: number
  end: number
  playhead: number
  rect: DOMRect
  moved: boolean
}

function groupCheckboxState(group: TimelineGroup, selected: string[]): boolean | 'indeterminate' {
  const count = group.tracks.filter(track => selected.includes(track.id)).length
  return count === 0 ? false : count === group.tracks.length ? true : 'indeterminate'
}

function ActivityBars({ track }: { track: TimelineTrack }) {
  return <>
    {track.segments.map(segment => (
      <span
        key={segment.id}
        className="activity-bars"
        style={{ left: (segment.start / TOTAL_MINUTES * 100) + '%', width: ((segment.end - segment.start) / TOTAL_MINUTES * 100) + '%' }}
        title={`${segment.startUtc} – ${segment.endUtc} · ${segment.source === 'sqlite_closed_mxf' ? 'índice SQLite' : 'audit MXF fechado, sem índice'} · TI ${segment.trackInstanceUUID}`}
        aria-hidden="true"
      />
    ))}
  </>
}


export function PlayerView() {
    const groups = useTimelineStore(state => state.groups)
    const expanded = useTimelineStore(state => state.expanded)
    const selectedTracks = useTimelineStore(state => state.selectedTracks)
    const selectionStart = useTimelineStore(state => state.selectionStart)
    const selectionEnd = useTimelineStore(state => state.selectionEnd)
    const playhead = useTimelineStore(state => state.playhead)
    const zoom = useTimelineStore(state => state.zoom)
    const playing = useTimelineStore(state => state.playing)
    const panel = useTimelineStore(state => state.panel)
    const playbackMode = useTimelineStore(state => state.playbackMode)
    const toggleGroup = useTimelineStore(state => state.toggleGroup)
    const toggleTrack = useTimelineStore(state => state.toggleTrack)
    const setGroupSelected = useTimelineStore(state => state.setGroupSelected)
    const setSelection = useTimelineStore(state => state.setSelection)
    const setPlayhead = useTimelineStore(state => state.setPlayhead)
    const setZoom = useTimelineStore(state => state.setZoom)
    const setPlaying = useTimelineStore(state => state.setPlaying)
    const setPanel = useTimelineStore(state => state.setPanel)
    const setPlaybackMode = useTimelineStore(state => state.setPlaybackMode)
    const setGroups = useTimelineStore(state => state.setGroups)
    const [filterKind, setFilterKind] = useState<'ALL' | GroupKind>('ALL')
    const [onlySelected, setOnlySelected] = useState(false)
    const [volume, setVolume] = useState(78)
    const [data, setData] = useState<TimelineData | null>(null)
    const [query, setQuery] = useState<{ date?: string; start?: string }>({})
    const [loading, setLoading] = useState(true)
    const [loadError, setLoadError] = useState('')
    const [audioStatus, setAudioStatus] = useState('')
    const [audioLoading, setAudioLoading] = useState(false)
    const [axisBaseWidth, setAxisBaseWidth] = useState(1230)
    const axisRef = useRef<HTMLDivElement>(null)
    const overviewRef = useRef<HTMLDivElement>(null)
    const scrollRef = useRef<HTMLDivElement>(null)
    const dragRef = useRef<DragState | null>(null)
    const audioRef = useRef<HTMLAudioElement>(null)
    const audioAnchorRef = useRef(0)
    const audioInstanceRef = useRef('')
  
    const pauseAudio = () => {
      audioRef.current?.pause()
      setPlaying(false)
    }
  
    const toggleAudio = async () => {
      const audio = audioRef.current
      if (!audio || audioLoading) return
      if (playing) { pauseAudio(); return }
      const tracks = groups.flatMap(group => group.tracks).filter(track => selectedTracks.includes(track.id))
      if (tracks.length !== 1) { setAudioStatus('Marque exatamente uma trilha para ouvir o MXF.'); return }
      const track = tracks[0]
      const segment = track.segments.find(item => item.start <= playhead && item.end > playhead)
        ?? track.segments.find(item => item.start >= playhead)
      if (!segment) { setAudioStatus('Nenhum áudio gravado após a agulha nesta janela.'); return }
      if (audioInstanceRef.current === segment.trackInstanceUUID && audio.src && audio.currentTime < audio.duration) {
        try { await audio.play(); setPlaying(true); return } catch { /* Reload the verified preview below. */ }
      }
      const firstInFile = track.segments.find(item => item.trackInstanceUUID === segment.trackInstanceUUID) ?? segment
      setAudioLoading(true)
      setAudioStatus('Preparando áudio do MXF fechado…')
      try {
        const response = await fetch('/api/preview', { method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ logical_track_uuid: track.logicalTrackUUID, track_instance_uuid: segment.trackInstanceUUID }) })
        const body = await response.json()
        if (!response.ok) throw new Error(body.error || `HTTP ${response.status}`)
        if (body.scope !== 'closed_mxf_technical_preview') throw new Error('Prévia sem origem MXF validada.')
        audio.pause()
        audio.src = body.audio_url
        audioInstanceRef.current = segment.trackInstanceUUID
        audio.volume = volume / 100
        audioAnchorRef.current = firstInFile.start
        setPlayhead(firstInFile.start)
        await audio.play()
        setPlaying(true)
        setAudioStatus(`Prévia técnica de ${track.label} · ${body.cache?.hit ? 'cache' : 'MXF decodificado'} · sem Evidence Bundle`)
      } catch (error) {
        setPlaying(false)
        setAudioStatus(error instanceof Error ? error.message : String(error))
      } finally { setAudioLoading(false) }
    }
  
    useEffect(() => {
      const controller = new AbortController()
      const params = new URLSearchParams()
      if (query.date) params.set('date', query.date)
      if (query.start) params.set('start', query.start)
      setLoading(true)
      setLoadError('')
      setAudioStatus('')
      fetch('/api/timeline' + (params.size ? '?' + params.toString() : ''), { signal: controller.signal })
        .then(async response => {
          const body = await response.json()
          if (!response.ok) throw new Error(body.error || `HTTP ${response.status}`)
          return fromApiTimeline(body)
        })
        .then(result => {
          audioRef.current?.pause()
          audioInstanceRef.current = ''
          setData(result)
          setGroups(result.groups)
          const first = result.groups.flatMap(group => group.tracks).flatMap(track => track.segments)[0]
          setPlayhead(first?.start ?? 0)
          setLoading(false)
        })
        .catch(error => { if (error.name !== 'AbortError') { setLoadError(String(error.message || error)); setLoading(false) } })
      return () => controller.abort()
    }, [query, setGroups, setPlayhead])
  
    const clock = (minute: number, seconds = false) => data ? formatClock(minute, data.windowStartUtc, seconds) : '--:--'
    const day = (minute: number) => data
      ? new Intl.DateTimeFormat('pt-BR', { timeZone: 'America/Sao_Paulo', day: '2-digit', month: '2-digit', year: 'numeric' })
        .format(new Date(Date.parse(data.windowStartUtc) + minute * 60000))
      : '--/--/----'
  
    useEffect(() => {
      const target = scrollRef.current
      if (!target) return
      const observer = new ResizeObserver(() => setAxisBaseWidth(Math.max(AXIS_MIN_WIDTH, target.clientWidth - LABEL_WIDTH)))
      observer.observe(target)
      return () => observer.disconnect()
    }, [])
  
    const visibleGroups = useMemo(() => groups
      .filter(group => filterKind === 'ALL' || group.kind === filterKind)
      .map(group => onlySelected
        ? { ...group, tracks: group.tracks.filter(track => selectedTracks.includes(track.id)) }
        : group)
      .filter(group => group.tracks.length > 0), [groups, filterKind, onlySelected, selectedTracks])
  
    const axisWidth = axisBaseWidth * zoom
    const currentWithinSelection = Math.max(selectionStart, Math.min(selectionEnd, playhead))
    const progressPercent = (currentWithinSelection - selectionStart) / Math.max(0.01, selectionEnd - selectionStart) * 100
  
    useEffect(() => { if (audioRef.current) audioRef.current.volume = volume / 100 }, [volume])
  
    useEffect(() => {
      const onPointerMove = (event: PointerEvent) => {
        const drag = dragRef.current
        if (!drag) return
        const delta = (event.clientX - drag.originX) / drag.rect.width * TOTAL_MINUTES
        const minute = clampMinute((event.clientX - drag.rect.left) / drag.rect.width * TOTAL_MINUTES)
        drag.moved ||= Math.abs(event.clientX - drag.originX) > 3
        if (drag.mode === 'playhead') setPlayhead(minute)
        if (drag.mode === 'start') setSelection(Math.min(drag.end - 0.25, drag.start + delta), drag.end)
        if (drag.mode === 'end') setSelection(drag.start, Math.max(drag.start + 0.25, drag.end + delta))
        if (drag.mode === 'move') {
          const length = drag.end - drag.start
          const start = Math.max(0, Math.min(TOTAL_MINUTES - length, drag.start + delta))
          setSelection(start, start + length)
        }
        if (drag.mode === 'create' && drag.moved) setSelection(drag.originMinute, minute)
      }
      const onPointerUp = () => {
        const drag = dragRef.current
        if (drag?.mode === 'create' && !drag.moved) setPlayhead(drag.originMinute)
        dragRef.current = null
      }
      window.addEventListener('pointermove', onPointerMove)
      window.addEventListener('pointerup', onPointerUp)
      return () => {
        window.removeEventListener('pointermove', onPointerMove)
        window.removeEventListener('pointerup', onPointerUp)
      }
    }, [setPlayhead, setSelection])
  
    const beginDrag = (event: ReactPointerEvent, mode: DragMode, rect: DOMRect) => {
      pauseAudio()
      event.preventDefault()
      event.stopPropagation()
      const originMinute = clampMinute((event.clientX - rect.left) / rect.width * TOTAL_MINUTES)
      dragRef.current = {
        mode, originX: event.clientX, originMinute, rect,
        start: selectionStart, end: selectionEnd, playhead, moved: false,
      }
      if (mode === 'playhead') setPlayhead(originMinute)
    }
  
    const beginAxisDrag = (event: ReactPointerEvent, mode: DragMode) => {
      if (axisRef.current) beginDrag(event, mode, axisRef.current.getBoundingClientRect())
    }
  
    const beginOverviewDrag = (event: ReactPointerEvent, mode: DragMode) => {
      if (overviewRef.current) beginDrag(event, mode, overviewRef.current.getBoundingClientRect())
    }
  
    const jumpToActivity = (direction: -1 | 1) => {
      pauseAudio()
      const positions = groups.flatMap(group => group.tracks)
        .filter(track => selectedTracks.includes(track.id))
        .flatMap(track => track.segments.map(segment => segment.start))
        .filter(minute => minute >= selectionStart && minute <= selectionEnd)
        .sort((a, b) => a - b)
      const next = direction === 1
        ? positions.find(minute => minute > playhead + 0.01)
        : positions.reverse().find(minute => minute < playhead - 0.01)
      setPlayhead(next ?? (direction === 1 ? selectionEnd : selectionStart))
    }
  
  return <>
  <main className="main-area">
    <header className="topbar">
      <div className="topbar-title"><strong>DATA/HORA - TIMELINE</strong><span className="topbar-divider" />
        <span>{day(0)} &nbsp; {clock(0, true)} &nbsp;–&nbsp; {day(TOTAL_MINUTES)} &nbsp; {clock(TOTAL_MINUTES, true)} &nbsp; ({formatDuration(TOTAL_MINUTES)})</span></div>
      <div className="topbar-actions"><span className="demo-badge">MXF FECHADO · {data?.counts.indexed_intervals ?? 0} INDEXADOS / {data?.counts.unindexed_intervals ?? 0} SEM ÍNDICE</span>
        <button className="timezone-button" type="button" onClick={() => setPanel('settings')}>UTC −03:00 (Brasília) <ChevronDown size={16} /></button>
        <label className="date-button" title="Escolher data"><CalendarDays size={20} /><input type="date" value={data?.date ?? ''} onChange={event => setQuery({ date: event.target.value })} aria-label="Escolher data" /></label>
      </div>
    </header>
  
    <section className="timeline-page" aria-label="Timeline multitrilha">
      <div className="timeline-toolbar">
        <div className="toolbar-description"><span>LINHAS DE ATIVIDADE</span><small>{loading ? 'Carregando intervalos gravados…' : loadError || audioStatus || `${data?.counts.logical_tracks ?? 0} trilha(s) · ${data?.counts.media_intervals ?? 0} intervalo(s) · marque uma trilha para ouvir`}</small></div>
        <div className="zoom-controls">
          <button type="button" aria-label="Reduzir zoom" onClick={() => setZoom(zoom - 0.25)}><ZoomOut size={19} /></button>
          <Slider aria-label="Zoom horizontal" min={1} max={4} step={0.25} value={[zoom]} onValueChange={value => setZoom(value[0] ?? 1)} />
          <button type="button" aria-label="Aumentar zoom" onClick={() => setZoom(zoom + 0.25)}><ZoomIn size={19} /></button>
          <span className="zoom-value">{Math.round(zoom * 100)}%</span>
        </div>
      </div>
  
      <div className="timeline-scroll" ref={scrollRef}>
        <div className="timeline-stage" style={{ width: LABEL_WIDTH + axisWidth }}>
          <div className="ruler-row">
            <div className="ruler-spacer" />
            <div className="time-axis" ref={axisRef} onPointerDown={event => beginAxisDrag(event, 'playhead')}>
              {Array.from({ length: 61 }, (_, index) => {
                const minute = index * 2
                return <div key={minute} className={'ruler-tick' + (minute % 10 === 0 ? ' major' : '')}
                  style={{ left: (minute / TOTAL_MINUTES * 100) + '%' }}>
                  {minute % 10 === 0 && <span>{clock(minute)}</span>}
                </div>
              })}
            </div>
          </div>
  
          <div className="timeline-groups">
            {!loading && !loadError && visibleGroups.length === 0 && <div className="timeline-empty">Nenhum intervalo de áudio gravado nesta janela. Escolha outra data ou horário em Configurações.</div>}
            {loadError && <div className="timeline-empty error">Falha ao carregar a timeline: {loadError}</div>}
            {visibleGroups.map(group => {
              const checked = groupCheckboxState(group, selectedTracks)
              const isOpen = expanded.includes(group.id)
              return <Collapsible key={group.id} open={isOpen} onOpenChange={() => toggleGroup(group.id)} className="timeline-group">
                <div className="group-header">
                  <button type="button" className="group-toggle" aria-label={(isOpen ? 'Recolher ' : 'Expandir ') + group.label}
                    aria-expanded={isOpen} onClick={() => toggleGroup(group.id)}>
                    <ChevronDown className={isOpen ? '' : 'rotated'} size={20} fill="currentColor" />
                  </button>
                  <Checkbox aria-label={'Selecionar todas as trilhas de ' + group.label} checked={checked}
                    onCheckedChange={value => setGroupSelected(group.id, value === true)} />
                  <strong>{group.label}</strong><span className="group-kind">{group.kind}</span>
                  <span className="group-count">{group.tracks.length} faixas</span>
                  <button className="group-more" type="button" aria-label={'Opções de ' + group.label} onClick={() => setPanel('filters')}><MoreHorizontal size={19} /></button>
                </div>
                <CollapsibleContent>
                  {group.tracks.map(track => {
                    const selected = selectedTracks.includes(track.id)
                    return <div className={'track-row' + (selected ? '' : ' unselected')} key={track.id}>
                      <div className="track-label">
                        <Checkbox aria-label={'Selecionar ' + track.label + ' de ' + group.label} checked={selected}
                          onCheckedChange={() => toggleTrack(track.id)} />
                        <span title={`LT ${track.logicalTrackUUID} · ${track.sources.includes('sqlite_closed_mxf') ? 'índice SQLite' : 'audit do Recorder, sem índice'}`}>{track.label}</span>
                      </div>
                      <div className="track-lane" onPointerDown={event => beginAxisDrag(event, 'create')}
                        aria-label={track.label + ' de ' + group.label}>
                        <div className="lane-dash" />
                        <ActivityBars track={track} />
                        <span className="outside-shade left" style={{ width: (selectionStart / TOTAL_MINUTES * 100) + '%' }} aria-hidden="true" />
                        <span className="outside-shade right" style={{ left: (selectionEnd / TOTAL_MINUTES * 100) + '%' }} aria-hidden="true" />
                      </div>
                    </div>
                  })}
                </CollapsibleContent>
              </Collapsible>
            })}
          </div>
  
          <div className="selection-edge start" style={{ left: LABEL_WIDTH + selectionStart / TOTAL_MINUTES * axisWidth }}
            onPointerDown={event => { event.currentTarget.focus(); beginAxisDrag(event, 'start') }} role="slider" tabIndex={0}
            aria-label="Início do período selecionado" aria-valuemin={0} aria-valuemax={selectionEnd}
            aria-valuenow={selectionStart} onKeyDown={event => {
              if (event.key === 'ArrowLeft') setSelection(selectionStart - 0.25, selectionEnd)
              if (event.key === 'ArrowRight') setSelection(selectionStart + 0.25, selectionEnd)
            }}><span /></div>
          <div className="selection-span-handle"
            style={{ left: LABEL_WIDTH + selectionStart / TOTAL_MINUTES * axisWidth,
              width: (selectionEnd - selectionStart) / TOTAL_MINUTES * axisWidth }}
            role="button" tabIndex={0} aria-label="Mover período selecionado"
            onPointerDown={event => beginAxisDrag(event, 'move')}
            onKeyDown={event => {
              const delta = event.key === 'ArrowLeft' ? -0.25 : event.key === 'ArrowRight' ? 0.25 : 0
              if (delta) { event.preventDefault(); setSelection(selectionStart + delta, selectionEnd + delta) }
            }} />
          <div className="selection-edge end" style={{ left: LABEL_WIDTH + selectionEnd / TOTAL_MINUTES * axisWidth }}
            onPointerDown={event => { event.currentTarget.focus(); beginAxisDrag(event, 'end') }} role="slider" tabIndex={0}
            aria-label="Fim do período selecionado" aria-valuemin={selectionStart} aria-valuemax={TOTAL_MINUTES}
            aria-valuenow={selectionEnd} onKeyDown={event => {
              if (event.key === 'ArrowLeft') setSelection(selectionStart, selectionEnd - 0.25)
              if (event.key === 'ArrowRight') setSelection(selectionStart, selectionEnd + 0.25)
            }}><span /></div>
          <div className="playhead-line" style={{ left: LABEL_WIDTH + playhead / TOTAL_MINUTES * axisWidth }}>
            <button type="button" className="playhead-grip" aria-label={'Agulha em ' + clock(playhead, true)}
              onPointerDown={event => beginAxisDrag(event, 'playhead')}
              onKeyDown={event => {
                if (event.key === 'ArrowLeft') setPlayhead(playhead - 1 / 60)
                if (event.key === 'ArrowRight') setPlayhead(playhead + 1 / 60)
              }} />
          </div>
        </div>
      </div>
    </section>
  </main>
  
  <footer className="bottom-dock">
    <div className="overview-row">
      <div className="footer-label"><strong>VISÃO GERAL DO PERÍODO</strong><span>{day(0)} &nbsp; {clock(0, true)} – {day(TOTAL_MINUTES)} {clock(TOTAL_MINUTES, true)}</span></div>
      <div className="overview-content">
        <div className="overview-times">{Array.from({ length: 13 }, (_, index) =>
          <span key={index}>{clock(index * 10)}</span>)}</div>
        <div className="overview-track" ref={overviewRef} onPointerDown={event => beginOverviewDrag(event, 'create')}>
          {groups.flatMap(group => group.tracks).flatMap(track => track.segments).map((segment, index) =>
            <span key={index} className="overview-activity" style={{ left: (segment.start / TOTAL_MINUTES * 100) + '%',
              width: Math.max(0.25, (segment.end - segment.start) / TOTAL_MINUTES * 100) + '%' }} />)}
          <span className="overview-shade left" style={{ width: (selectionStart / TOTAL_MINUTES * 100) + '%' }} />
          <span className="overview-shade right" style={{ left: (selectionEnd / TOTAL_MINUTES * 100) + '%' }} />
          <span className="overview-selection" style={{ left: (selectionStart / TOTAL_MINUTES * 100) + '%',
            width: ((selectionEnd - selectionStart) / TOTAL_MINUTES * 100) + '%' }}
            onPointerDown={event => beginOverviewDrag(event, 'move')} />
          <button className="overview-handle start" type="button" aria-label="Arrastar início do período"
            style={{ left: (selectionStart / TOTAL_MINUTES * 100) + '%' }}
            onPointerDown={event => beginOverviewDrag(event, 'start')} />
          <button className="overview-handle end" type="button" aria-label="Arrastar fim do período"
            style={{ left: (selectionEnd / TOTAL_MINUTES * 100) + '%' }}
            onPointerDown={event => beginOverviewDrag(event, 'end')} />
          <span className="overview-playhead" style={{ left: (playhead / TOTAL_MINUTES * 100) + '%' }} />
        </div>
      </div>
    </div>
    <div className="transport-row">
      <div className="footer-label selected-period"><strong>PERÍODO SELECIONADO</strong>
        <span>{day(selectionStart)} &nbsp; {clock(selectionStart, true)} – {day(selectionEnd)} {clock(selectionEnd, true)} &nbsp; ({formatDuration(selectionEnd - selectionStart)})</span></div>
      <div className="transport-controls">
        <button type="button" aria-label="Ir ao áudio anterior" onClick={() => jumpToActivity(-1)}><ChevronLeft size={21} /></button>
        <button type="button" aria-label="Voltar ao início" onClick={() => { pauseAudio(); setPlayhead(selectionStart) }}><SkipBack size={21} fill="currentColor" /></button>
        <button type="button" aria-label="Retroceder dez segundos" onClick={() => { pauseAudio(); setPlayhead(Math.max(selectionStart, playhead - 1 / 6)) }}><RotateCcw size={22} /><small>10s</small></button>
        <button type="button" className="play-button" aria-label={playing ? 'Pausar áudio MXF' : 'Ouvir áudio MXF na agulha'}
          disabled={audioLoading || loading || !!loadError} onClick={toggleAudio}>
          {playing ? <Pause size={23} fill="currentColor" /> : <Play size={23} fill="currentColor" />}</button>
        <button type="button" aria-label="Avançar dez segundos" onClick={() => { pauseAudio(); setPlayhead(Math.min(selectionEnd, playhead + 1 / 6)) }}><RotateCw size={22} /><small>10s</small></button>
        <button type="button" aria-label="Ir ao próximo áudio" onClick={() => jumpToActivity(1)}><SkipForward size={21} fill="currentColor" /></button>
      </div>
      <div className="scrub-controls">
        <span>{clock(currentWithinSelection, true)}</span>
        <input type="range" min={0} max={1000} value={Math.round(progressPercent * 10)} aria-label="Posição no período selecionado"
          onChange={event => { pauseAudio(); setPlayhead(selectionStart + Number(event.target.value) / 1000 * (selectionEnd - selectionStart)) }} />
        <span>{clock(selectionEnd, true)}</span>
      </div>
      <div className="volume-controls"><Volume2 size={20} /><input type="range" min={0} max={100} value={volume}
        aria-label="Volume" onChange={event => setVolume(Number(event.target.value))} />
        <button type="button" aria-label="Opções de reprodução" onClick={() => setPanel('preferences')}><MoreHorizontal size={20} /></button></div>
    </div>
  </footer>
  <audio ref={audioRef} hidden onTimeUpdate={event => setPlayhead(audioAnchorRef.current + event.currentTarget.currentTime / 60)}
    onEnded={() => setPlaying(false)} onError={() => { setPlaying(false); setAudioStatus('Falha ao reproduzir o áudio decodificado.') }} />
  
  <Sheet open={panel !== null} onOpenChange={open => !open && setPanel(null)}>
    <SheetContent side="right" className="panel-sheet">
      <SheetHeader><SheetTitle>{panel === 'export' ? 'Exportar período' : panel === 'filters' ? 'Filtros' :
        panel === 'settings' ? 'Configurações' : panel === 'session' ? 'Sessão' : 'Preferências'}</SheetTitle>
        <SheetDescription>Timeline observada em MXFs fechados. Intervalos sem índice são navegação técnica e não constituem Evidence Bundle.</SheetDescription></SheetHeader>
      <div className="sheet-body">
        {panel === 'export' && <><p><strong>{selectedTracks.length}</strong> trilhas selecionadas</p>
          <p>{clock(selectionStart, true)} – {clock(selectionEnd, true)} ({formatDuration(selectionEnd - selectionStart)})</p>
          <p>Exportação pela seleção ainda requer o plano histórico e a cadeia de integridade.</p>
          <Button disabled>Gerar Evidence Bundle</Button></>}
        {panel === 'filters' && <><label htmlFor="kind-filter">Tipo de grupo</label>
          <select id="kind-filter" value={filterKind} onChange={event => setFilterKind(event.target.value as 'ALL' | GroupKind)}>
            <option value="ALL">Todos</option><option value="CWP">CWP</option><option value="TEL">TEL</option><option value="RADIO">RADIO</option>
          </select><label className="sheet-check"><Checkbox checked={onlySelected} onCheckedChange={value => setOnlySelected(value === true)} />Somente trilhas marcadas</label></>}
        {panel === 'settings' && <><label htmlFor="date-setting">Data da gravação</label><input id="date-setting" type="date" value={data?.date ?? ''} onChange={event => setQuery({ date: event.target.value })} />
          <label htmlFor="start-setting">Início da janela (2 horas)</label><input id="start-setting" type="time" value={data?.startLocal ?? ''} onChange={event => setQuery({ date: data?.date, start: event.target.value })} />
          <p>Fuso exibido: UTC −03:00 (Brasília)</p><p>Escala horizontal: {Math.round(zoom * 100)}%</p></>}
        {panel === 'session' && <><p>Data: {day(0)}</p><p>Período: {clock(0)}–{clock(TOTAL_MINUTES)}</p>
          <p>Origem: índice SQLite de MXF fechado e audit de execuções operacionais fechadas.</p>
          <p>{data?.counts.indexed_intervals ?? 0} intervalos indexados; {data?.counts.unindexed_intervals ?? 0} intervalos sem índice. Áudio gerado pelo simulador continua identificado como teste.</p></>}
        {panel === 'preferences' && <><label htmlFor="mode-select">Modo previsto de reprodução</label>
          <select id="mode-select" value={playbackMode} onChange={event => setPlaybackMode(event.target.value as typeof playbackMode)}>
            <option value="continuous">CONTINUOUS</option><option value="only-audio">ONLY AUDIO</option><option value="only-activity">ONLY ACTIVITY</option></select>
          <p>Os modos ainda aguardam ligação ao áudio histórico verificado.</p></>}
      </div>
    </SheetContent>
  </Sheet>
  </>
}
