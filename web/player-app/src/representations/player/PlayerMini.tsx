import { Pause, Play } from 'lucide-react'

export function PlayerMini({ playing = false, current = '00:00', duration = '00:00', onToggle, label }: {
  playing?: boolean
  current?: string
  duration?: string
  onToggle?: () => void
  label?: string
}) {
  return <div className="rep-player-mini">
    {label && <span className="rep-player-mini-label">{label}</span>}
    <button type="button" onClick={onToggle} aria-label={playing ? 'Pausar' : 'Reproduzir'}>
      {playing ? <Pause size={16} /> : <Play size={16} />}
    </button>
    <strong>{current}</strong><span>/ {duration}</span>
  </div>
}
