import { Plus } from 'lucide-react'
import { CwpCard } from './CwpCard'
import { SIM_CWPS, type SimulatorMode } from '../model'
export function SidePanel({ side, mode, expanded, setExpanded }: { side: 'A' | 'B'; mode: SimulatorMode; expanded: string[]; setExpanded: (next: string[]) => void }) {
  const cwps = SIM_CWPS.filter(cwp => cwp.side === side)
  const colorClass = side === 'A' ? 'side-a' : 'side-b'
  const totalServices = cwps.reduce((sum, cwp) => sum + cwp[mode].services.length, 0)
  const title = side === 'A' ? 'Lado A' : 'Lado B'
  return <section className={`sim-side-card ${colorClass}`}>
    <header><div><h2>{title}</h2><p>{side === 'A' ? 'CWPs que se comunicam com o Lado B' : 'CWPs que se comunicam com o Lado A'}</p></div><span>{totalServices} serviços</span></header>
    <div className="cwp-list">{cwps.map(cwp => <CwpCard key={cwp.id} cwp={cwp} mode={mode} expanded={expanded.includes(cwp.id)}
      onToggle={() => setExpanded(expanded.includes(cwp.id) ? expanded.filter(id => id !== cwp.id) : [...expanded, cwp.id])} />)}</div>
    <button type="button" className="add-cwp"><Plus size={18} />Adicionar CWP</button>
  </section>
}

