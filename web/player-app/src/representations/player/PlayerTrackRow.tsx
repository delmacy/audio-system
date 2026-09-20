import { ThemedCheckbox } from '@/components/themed-ui'

export type PlayerTrackRowProps = {
  label: string
  group: string
  logicalTrackUUID: string
  mxfName: string
  trackIndex: number
  segmentCount: number
  duration: string
  selected: boolean
  onSelectedChange?: (selected: boolean) => void
}

export function PlayerTrackRow({
  label,
  group,
  logicalTrackUUID,
  mxfName,
  trackIndex,
  segmentCount,
  duration,
  selected,
  onSelectedChange,
}: PlayerTrackRowProps) {
  return <article className={`rep-player-track-row ${selected ? 'selected' : 'muted'}`}>
    <label className="rep-player-track-check">
      <ThemedCheckbox
        color={selected ? 'blue' : 'gray'}
        checked={selected}
        onCheckedChange={value => onSelectedChange?.(value === true)}
        aria-label={`${selected ? 'Remover' : 'Adicionar'} ${label} da escuta`}
      />
      <span>ouvir</span>
    </label>

    <div className="rep-player-track-main">
      <small>{group}</small>
      <strong>{label}</strong>
      <code title={logicalTrackUUID}>{logicalTrackUUID}</code>
      <span className="rep-player-track-file">{mxfName} · track {trackIndex}</span>
    </div>

    <div className="rep-player-track-stat">
      <span>segmentos</span>
      <strong>{segmentCount}</strong>
    </div>

    <div className="rep-player-track-stat">
      <span>gravado</span>
      <strong>{duration}</strong>
    </div>
  </article>
}
