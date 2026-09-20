import { Pause, Play, Square } from 'lucide-react'
import { ThemedButton } from '@/components/themed-ui'

export type PlayerTransportProps = {
  playing?: boolean
  loading?: boolean
  selectedCount?: number
  onPlay?: () => void
  onStop?: () => void
}

export function PlayerTransport({
  playing = false,
  loading = false,
  selectedCount = 0,
  onPlay,
  onStop,
}: PlayerTransportProps) {
  return <div className="rep-player-transport">
    <div className="rep-player-transport-status">
      <span className={playing ? 'playing' : loading ? 'loading' : ''} />
      <div>
        <strong>{playing ? 'reproduzindo' : loading ? 'preparando áudio' : 'pronto para escuta'}</strong>
        <small>{selectedCount} trilha(s) selecionada(s)</small>
      </div>
    </div>

    <div className="rep-player-transport-actions">
      <ThemedButton
        id="button_blue_icon_play"
        color="blue"
        size="sm"
        onClick={onPlay}
        disabled={loading || selectedCount === 0}
        aria-label={playing ? 'Reiniciar reprodução' : 'Reproduzir trilhas selecionadas'}
      >
        {playing ? <Pause size={15} /> : <Play size={15} />}
        {loading ? 'Preparando...' : playing ? 'Reiniciar' : 'Ouvir selecionadas'}
      </ThemedButton>
      <ThemedButton
        id="button_gray_icon_square"
        color="gray"
        size="sm"
        onClick={onStop}
        disabled={!playing}
        aria-label="Parar reprodução"
      >
        <Square size={14} />
        Parar
      </ThemedButton>
    </div>
  </div>
}
