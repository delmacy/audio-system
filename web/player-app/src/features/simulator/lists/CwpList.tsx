import { CwpListItem, CwpOperation } from '@/representations/cwp'
import type { CwpConfig, SimulatorMode } from '../model'

export function CwpList({ cwps, mode, expanded, setExpanded }: {
  cwps: CwpConfig[]
  mode: SimulatorMode
  expanded: string[]
  setExpanded: (next: string[]) => void
}) {
  return <div className="cwp-list">
    {cwps.map(cwp => {
      const isExpanded = expanded.includes(cwp.id)
      return <div key={cwp.id} className="cwp-list-entry">
        <CwpListItem
          cwp={cwp}
          mode={mode}
          onClick={() => setExpanded(
            isExpanded
              ? expanded.filter(id => id !== cwp.id)
              : [...expanded, cwp.id],
          )}
        />
        {isExpanded && <CwpOperation cwp={cwp} mode={mode} />}
      </div>
    })}
  </div>
}
