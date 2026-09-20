import { Plus } from 'lucide-react'
import { CwpList } from '../lists/CwpList'
import { SIM_CWPS, type SimulatorMode } from '../model'

export function SideBlock({ side, mode, expanded, setExpanded }: {
  side: 'A' | 'B'
  mode: SimulatorMode
  expanded: string[]
  setExpanded: (next: string[]) => void
}) {
  const cwps = SIM_CWPS.filter(cwp => cwp.side === side)
  const colorClass = side === 'A' ? 'side-a' : 'side-b'
  const totalServices = cwps.reduce((sum, cwp) => sum + cwp[mode].services.length, 0)
  const title = side === 'A' ? 'Lado A' : 'Lado B'

  return <section className={`sim-side-card ${colorClass}`}>
    <header>
      <div>
        <h2>{title}</h2>
        <p>{side === 'A' ? 'CWPs que se comunicam com o Lado B' : 'CWPs que se comunicam com o Lado A'}</p>
      </div>
      <span>{totalServices} serviços</span>
    </header>

    <CwpList cwps={cwps} mode={mode} expanded={expanded} setExpanded={setExpanded} />

    <button type="button" className="add-cwp"><Plus size={18} />Adicionar CWP</button>
  </section>
}
