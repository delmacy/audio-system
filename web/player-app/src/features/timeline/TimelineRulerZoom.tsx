import { useMemo, useRef, useState } from 'react'
import { Maximize2, Minus, Plus } from 'lucide-react'

const MAX_VISIBLE_SECONDS = 5 * 60 * 60
const MIN_VISIBLE_SECONDS = 25
const NICE_MAJOR_STEPS = [5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]

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

function visibleFromZoom(zoom: number, duration: number) {
  const maxVisible = Math.min(MAX_VISIBLE_SECONDS, duration)
  const minVisible = Math.min(MIN_VISIBLE_SECONDS, maxVisible)
  if (maxVisible <= minVisible) return maxVisible
  const ratio = clamp(zoom, 0, 100) / 100
  return maxVisible * Math.pow(minVisible / maxVisible, ratio)
}

function chooseMajorStep(visibleDuration: number) {
  const target = visibleDuration / 5
  let best = NICE_MAJOR_STEPS[0]
  let bestDistance = Math.abs(Math.log(target / best))
  for (const step of NICE_MAJOR_STEPS) {
    const distance = Math.abs(Math.log(target / step))
    if (distance < bestDistance) {
      best = step
      bestDistance = distance
    }
  }
  return best
}

export function TimelineRulerZoom({
  durationSeconds = 8 * 60 * 60,
  initialStartSeconds = 0,
}: {
  durationSeconds?: number
  initialStartSeconds?: number
}) {
  const safeDuration = Math.max(1, durationSeconds)
  const axisRef = useRef<HTMLDivElement>(null)
  const dragRef = useRef<{ x: number; start: number } | null>(null)

  const [zoom, setZoom] = useState(0)
  const [viewportStart, setViewportStart] = useState(clamp(initialStartSeconds, 0, safeDuration - 1))
  const [dragging, setDragging] = useState(false)

  const visibleDuration = visibleFromZoom(zoom, safeDuration)
  const maxStart = Math.max(0, safeDuration - visibleDuration)
  const safeStart = clamp(viewportStart, 0, maxStart)
  const end = safeStart + visibleDuration
  const majorStep = chooseMajorStep(visibleDuration)
  const minorStep = majorStep / 5

  const ticks = useMemo(() => {
    const first = Math.ceil(safeStart / minorStep) * minorStep
    const items: { time: number; major: boolean }[] = []
    for (let t = first; t <= end + 0.0001; t += minorStep) {
      items.push({
        time: t,
        major: Math.abs((t / majorStep) - Math.round(t / majorStep)) < 0.001,
      })
      if (items.length > 220) break
    }
    return items
  }, [safeStart, end, minorStep, majorStep])

  const setZoomAtAnchor = (nextZoom: number, anchor = 0.5) => {
    const z = clamp(nextZoom, 0, 100)
    const boundedAnchor = clamp(anchor, 0, 1)
    const anchorTime = safeStart + visibleDuration * boundedAnchor
    const nextVisible = visibleFromZoom(z, safeDuration)
    const nextStart = anchorTime - nextVisible * boundedAnchor

    setZoom(z)
    setViewportStart(clamp(nextStart, 0, Math.max(0, safeDuration - nextVisible)))
  }

  const panBySeconds = (seconds: number) => {
    setViewportStart(clamp(safeStart + seconds, 0, maxStart))
  }

  const onPointerDown = (event: React.PointerEvent<HTMLDivElement>) => {
    if (event.button !== 0) return
    event.currentTarget.setPointerCapture(event.pointerId)
    dragRef.current = { x: event.clientX, start: safeStart }
    setDragging(true)
  }

  const onPointerMove = (event: React.PointerEvent<HTMLDivElement>) => {
    const drag = dragRef.current
    const width = axisRef.current?.getBoundingClientRect().width ?? 0
    if (!drag || width <= 0) return
    const deltaPixels = event.clientX - drag.x
    const deltaSeconds = -(deltaPixels / width) * visibleDuration
    setViewportStart(clamp(drag.start + deltaSeconds, 0, maxStart))
  }

  const finishDrag = (event: React.PointerEvent<HTMLDivElement>) => {
    if (dragRef.current) {
      dragRef.current = null
      setDragging(false)
    }
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId)
    }
  }

  const onWheel = (event: React.WheelEvent<HTMLDivElement>) => {
    if (event.ctrlKey || event.metaKey) {
      event.preventDefault()
      const rect = event.currentTarget.getBoundingClientRect()
      const anchor = rect.width > 0 ? (event.clientX - rect.left) / rect.width : 0.5
      setZoomAtAnchor(zoom + event.deltaY * 0.08, anchor)
      return
    }

    const delta = Math.abs(event.deltaX) > Math.abs(event.deltaY)
      ? event.deltaX
      : event.shiftKey
        ? event.deltaY
        : 0

    if (delta !== 0) {
      event.preventDefault()
      panBySeconds((delta / 600) * visibleDuration)
    }
  }

  const fitFiveHours = () => {
    setZoom(0)
    setViewportStart(0)
  }

  return <section className="timeline-ruler-zoom" aria-label="Régua temporal com zoom e deslocamento">
    <div className="timeline-ruler-zoom-toolbar">
      <div className="timeline-ruler-window-label">
        <strong>{formatTime(safeStart)}</strong>
        <span>→</span>
        <strong>{formatTime(end)}</strong>
        <small>{formatTime(visibleDuration)} visíveis · blocos {formatTime(majorStep)}</small>
      </div>

      <div className="timeline-ruler-zoom-controls">
        <button
          type="button"
          onClick={() => setZoomAtAnchor(zoom - 8)}
          disabled={zoom <= 0}
          aria-label="Diminuir zoom"
        ><Minus size={15}/></button>

        <input
          type="range"
          min="0"
          max="100"
          step="0.1"
          value={zoom}
          onChange={event => setZoomAtAnchor(Number(event.target.value))}
          aria-label="Zoom contínuo da timeline"
        />

        <span>{Math.round(zoom)}%</span>

        <button
          type="button"
          onClick={() => setZoomAtAnchor(zoom + 8)}
          disabled={zoom >= 100}
          aria-label="Aumentar zoom"
        ><Plus size={15}/></button>

        <button type="button" onClick={fitFiveHours} aria-label="Voltar para janela de cinco horas">
          <Maximize2 size={15}/>5h
        </button>
      </div>
    </div>

    <div
      ref={axisRef}
      className={`timeline-ruler-zoom-axis ${dragging ? 'dragging' : ''}`}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={finishDrag}
      onPointerCancel={finishDrag}
      onWheel={onWheel}
      title="Arraste para deslocar · Shift+roda/touchpad para pan · Ctrl+roda para zoom"
    >
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
