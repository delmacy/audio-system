import { ActiveServicesBlock } from './ActiveServicesBlock'
import { RecorderTopologyBlock } from './RecorderTopologyBlock'
import { SideBlock } from './SideBlock'
import type { SimStatus, SimulatorMode } from '../model'

export function SimulatorWorkspaceBlock({ mode, status, expanded, setExpanded }: {
  mode: SimulatorMode
  status: SimStatus
  expanded: string[]
  setExpanded: (next: string[]) => void
}) {
  return <section className="sim-workspace">
    <div className="sim-sides-layout">
      <SideBlock side="A" mode={mode} expanded={expanded} setExpanded={setExpanded} />
      <RecorderTopologyBlock mode={mode} status={status} />
      <SideBlock side="B" mode={mode} expanded={expanded} setExpanded={setExpanded} />
    </div>

    <ActiveServicesBlock mode={mode} />
  </section>
}
