import { useMemo, useState } from 'react'
import { Maximize2, Minus, Plus } from 'lucide-react'

const NICE_STEPS = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]

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

function chooseMajorStep(visibleDuration: number) {
  const target = visibleDuration / 6
  return NICE_STEPS.find(step => step >= target) ?? NICE_STEPS[NICE_STEPS.length - 1]
}

export function TimelineRulerZoom({
  durationSeconds = 3600,
  initialStartSeconds = 0,
}: {
  durationSeconds?: number
  initialStartSeconds?: number
}) {
  const safeDuration = Math.max(1, durationSeconds)
  const [zoom, setZoom] = useState(0)
  const [viewportStart, setViewportStart] = useState(clamp(initialStartSeconds, 0, safeDuration - 1))

  const visibleDuration = useMemo(() => {
    const minVisible = Math.min(10, safeDuration)
    const ratio = Math.pow(1 - zoom / 100, 2)
    return clamp(minVisible + (safeDuration - minVisible) * ratio, minVisible, safeDuration)
  }, [safeDuration, zoom])

  const safeStart = clamp(viewportStart, 0, Math.max(0, safeDuration - visibleDuration))
  if (safeStart !== viewportStart) {
    queueMicrotask(() => setViewportStart(safeStart))
  }

  const majorStep = chooseMajorStep(visibleDuration)
  const minorStep = majorStep / 5
  const end = safeStart + visibleDuration

  const ticks = useMemo(() => {
    const first = Math.ceil(safeStart / minorStep) * minorStep
    const items: { time: number; major: boolean }[] = []
    for (let t = first; t <= end + 0.0001; t += minorStep) {
      items.push({ time: t, major: Math.abs((t / majorStep) - Math.round(t / majorStep)) < 0.001 })
      if (items.length > 150) break
    }
    return items
  }, [safeStart, end, minorStep, majorStep])

  const setZoomKeepingCenter = (nextZoom: number) => {
    const center = safeStart + visibleDuration / 2
    const z = clamp(nextZoom, 0, 100)
    const minVisible = Math.min(10, safeDuration)
    const ratio = Math.pow(1 - z / 100, 2)
    const nextVisible = clamp(minVisible + (safeDuration - minVisible) * ratio, minVisible, safeDuration)
    setZoom(z)
    setViewportStart(clamp(center - nextVisible / 2, 0, Math.max(0, safeDuration - nextVisible)))
  }

  const fit = () => {
    setZoom(0)
    setViewportStart(0)
  }

  return <section className="timeline-ruler-zoom" aria-label="Régua temporal com zoom">
    <div className="timeline-ruler-zoom-toolbar">
      <div className="timeline-ruler-window-label">
        <strong>{formatTime(safeStart)}</strong>
        <span>→</span>
        <strong>{formatTime(end)}</strong>
        <small>{formatTime(visibleDuration)} visíveis</small>
      </div>

      <div className="timeline-ruler-zoom-controls">
        <button type="button" onClick={() => setZoomKeepingCenter(zoom - 10)} aria-label="Diminuir zoom"><Minus size={15}/></button>
        <input
          type="range"
          min="0"
          max="100"
          value={zoom}
          onChange={event => setZoomKeepingCenter(Number(event.target.value))}
          aria-label="Zoom da timeline"
        />
        <span>{zoom}%</span>
        <button type="button" onClick={() => setZoomKeepingCenter(zoom + 10)} aria-label="Aumentar zoom"><Plus size={15}/></button>
        <button type="button" onClick={fit} aria-label="Exibir toda a timeline"><Maximize2 size={15}/>Fit</button>
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
