import { useMemo, useState } from 'react'
import { PlayerTrackRow, type PlayerTrackRowProps } from './PlayerTrackRow'
import { PlayerTransport } from './PlayerTransport'

export type PlayerTrackSelectionProps = {
  tracks: Omit<PlayerTrackRowProps, 'selected' | 'onSelectedChange'>[]
}

export function PlayerTrackSelection({ tracks }: PlayerTrackSelectionProps) {
  const [selected, setSelected] = useState<string[]>(tracks.map(track => track.logicalTrackUUID))
  const [playing, setPlaying] = useState(false)

  const selectedCount = useMemo(
    () => tracks.filter(track => selected.includes(track.logicalTrackUUID)).length,
    [tracks, selected],
  )

  return <section className="rep-player-track-selection">
    <header>
      <div>
        <strong>Trilhas gravadas</strong>
        <small>seleção por faixa interna do MXF</small>
      </div>
      <span>{selectedCount}/{tracks.length}</span>
    </header>

    <div className="rep-player-track-selection-list">
      {tracks.map(track => <PlayerTrackRow
        key={track.logicalTrackUUID}
        {...track}
        selected={selected.includes(track.logicalTrackUUID)}
        onSelectedChange={checked => setSelected(current =>
          checked
            ? Array.from(new Set([...current, track.logicalTrackUUID]))
            : current.filter(id => id !== track.logicalTrackUUID),
        )}
      />)}
    </div>

    <PlayerTransport
      playing={playing}
      selectedCount={selectedCount}
      onPlay={() => setPlaying(true)}
      onStop={() => setPlaying(false)}
    />
  </section>
}
