import { PlayerMini } from './PlayerMini'

export function PlayerInline({ label, progress = 35 }: { label: string; progress?: number }) {
  return <div className="rep-player-inline">
    <strong>{label}</strong>
    <div className="rep-player-track"><i style={{ width: `${progress}%` }} /></div>
    <PlayerMini current="01:23" duration="04:50" />
  </div>
}
