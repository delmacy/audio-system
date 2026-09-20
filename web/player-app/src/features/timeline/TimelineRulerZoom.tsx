import { useMemo, useState } from 'react'
import { Maximize2, Minus, Plus } from 'lucide-react'

const ZOOM_LEVELS = [
  { visibleSeconds: 5 * 60 * 60, majorStep: 60 * 60, label: '5h / blocos 1h' },
  { visibleSeconds: 150 * 60, majorStep: 30 * 60, label: '2h30 / blocos 30min' },
  { visibleSeconds: 75 * 60, majorStep: 15 * 60, label: '1h15 / blocos 15min' },
  { visibleSeconds: 50 * 60, majorStep: 10 * 60, label: '50min / blocos 10min' },
  { visibleSeconds: 25 * 60, majorStep: 5 * 60, label: '25min / blocos 5min' },
  { visibleSeconds: 10 * 60, majorStep: 2 * 60, label: '10min / blocos 2min' },
  { visibleSeconds: 5 * 60, majorStep: 60, label: '5min / blocos 1min' },
  { visibleSeconds: 150, majorStep: 30, label: '2m30 / blocos 30s' },
  { visibleSeconds: 75, majorStep: 15, label: '1m15 / blocos 15s' },
  { visibleSeconds: 50, majorStep: 10, label: '50s / blocos 10s' },
  { visibleSeconds: 25, majorStep: 5, label: '25s / blocos 5s' },
] as const

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value))
}

function formatTime(totalSeconds: number) {
  const seconds = Math.max(0, Math.round(totalSeconds))
  const h = Math.floor(seconds / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  const s = seconds % 60
  return h > 0
    ? `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
    : `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
}

export function TimelineRulerZoom({
  durationSeconds = 8 * 60 * 60,
  initialStartSeconds = 0,
}: {
  durationSeconds?: number
  initialStartSeconds?: number
}) {
  const safeDuration = Math.max(1, durationSeconds)
  const [zoomLevel, setZoomLevel] = useState(0)
  const [viewportStart, setViewportStart] = useState(clamp(initialStartSeconds, 0, safeDuration - 1))

  const level = ZOOM_LEVELS[zoomLevel]
  const visibleDuration = Math.min(level.visibleSeconds, safeDuration)
  const majorStep = Math.min(level.majorStep, visibleDuration)
  const minorStep = majorStep / 5

  const safeStart = clamp(viewportStart, 0, Math.max(0, safeDuration - visibleDuration))
  const end = safeStart + visibleDuration

  const ticks = useMemo(() => {
    const first = Math.ceil(safeStart / minorStep) * minorStep
    const items: { time: number; major: boolean }[] = []
    for (let t = first; t <= end + 0.0001; t += minorStep) {
      items.push({
        time: t,
        major: Math.abs((t / majorStep) - Math.round(t / majorStep)) < 0.001,
      })
      if (items.length > 180) break
    }
    return items
  }, [safeStart, end, minorStep, majorStep])

  const setLevelKeepingCenter = (nextLevel: number) => {
    const center = safeStart + visibleDuration / 2
    const next = clamp(nextLevel, 0, ZOOM_LEVELS.length - 1)
    const nextVisible = Math.min(ZOOM_LEVELS[next].visibleSeconds, safeDuration)
    setZoomLevel(next)
    setViewportStart(clamp(
      center - nextVisible / 2,
      0,
      Math.max(0, safeDuration - nextVisible),
    ))
  }

  const fitFiveHours = () => {
    setZoomLevel(0)
    setViewportStart(0)
  }

  return <section className="timeline-ruler-zoom" aria-label="Régua temporal com zoom">
    <div className="timeline-ruler-zoom-toolbar">
      <div className="timeline-ruler-window-label">
        <strong>{formatTime(safeStart)}</strong>
        <span>→</span>
        <strong>{formatTime(end)}</strong>
        <small>{formatTime(visibleDuration)} visíveis · {level.label}</small>
      </div>

      <div className="timeline-ruler-zoom-controls">
        <button
          type="button"
          onClick={() => setLevelKeepingCenter(zoomLevel - 1)}
          disabled={zoomLevel === 0}
          aria-label="Diminuir zoom"
        ><Minus size={15}/></button>

        <input
          type="range"
          min="0"
          max={ZOOM_LEVELS.length - 1}
          step="1"
          value={zoomLevel}
          onChange={event => setLevelKeepingCenter(Number(event.target.value))}
          aria-label="Zoom da timeline"
        />

        <span>{zoomLevel + 1}/{ZOOM_LEVELS.length}</span>

        <button
          type="button"
          onClick={() => setLevelKeepingCenter(zoomLevel + 1)}
          disabled={zoomLevel === ZOOM_LEVELS.length - 1}
          aria-label="Aumentar zoom"
        ><Plus size={15}/></button>

        <button type="button" onClick={fitFiveHours} aria-label="Voltar para janela de cinco horas">
          <Maximize2 size={15}/>5h
        </button>
      </div>
    </div>

    <div className="timeline-ruler-zoom-axis">
      {ticks.map(tick => {
        const left = ((tick.time - safeStart) / visibleDuration) * 100
        return <i
          key={tick.time}
          className={tick.major ? 'major' : 'minor'}
          style={{ left: `${left}%` }}
        >
          {tick.major && <span>{formatTime(tick.time)}</span>}
        </i>
      })}
    </div>
  </section>
}
