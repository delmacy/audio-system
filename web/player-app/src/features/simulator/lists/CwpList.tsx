import { CwpFull } from '@/representations/cwp'
import type { CwpConfig, SimulatorMode } from '../model'

export function CwpList({ cwps, mode, expanded, setExpanded }: {
  cwps: CwpConfig[]
  mode: SimulatorMode
  expanded: string[]
  setExpanded: (next: string[]) => void
}) {
  return <div className="cwp-list">
    {cwps.map(cwp => <CwpFull
      key={cwp.id}
      cwp={cwp}
      mode={mode}
      expanded={expanded.includes(cwp.id)}
      onToggle={() => setExpanded(
        expanded.includes(cwp.id)
          ? expanded.filter(id => id !== cwp.id)
          : [...expanded, cwp.id],
      )}
    />)}
  </div>
}
