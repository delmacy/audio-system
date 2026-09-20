import { Pause, Play } from 'lucide-react'

export function PlayerMini({ playing = false, current = '00:00', duration = '00:00', onToggle }: {
  playing?: boolean
  current?: string
  duration?: string
  onToggle?: () => void
}) {
  return <div className="rep-player-mini">
    <button type="button" onClick={onToggle} aria-label={playing ? 'Pausar' : 'Reproduzir'}>
      {playing ? <Pause size={16} /> : <Play size={16} />}
    </button>
    <strong>{current}</strong><span>/ {duration}</span>
  </div>
}
