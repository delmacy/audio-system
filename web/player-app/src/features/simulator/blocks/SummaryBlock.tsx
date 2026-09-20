import { Activity, ClipboardList, Database, FileText, Phone, Radio } from 'lucide-react'
import { SummaryCard } from '../elements/SummaryCard'
import type { SimStatus } from '../model'

export function SummaryBlock({ simActive, status }: { simActive: boolean; status: SimStatus }) {
  return <section className="sim-summary-grid">
    <SummaryCard icon={ClipboardList} title="CWP's" value="4" detail="ativos de 4" />
    <SummaryCard icon={Radio} title="Rádios" value="8" detail="ativos de 8" tone="green" />
    <SummaryCard icon={Phone} title="Telefones" value="4" detail="ativos de 4" />
    <SummaryCard icon={Database} title="Serviços Total" value="16" detail="ativos" tone="green" />
    <SummaryCard icon={FileText} title="Cenário Atual" value="TWR - Pico Manhã" detail={simActive ? 'em edição' : 'captura corrente'} />
    <SummaryCard icon={Activity} title="Duração" value={simActive ? '00:30:00' : 'corrente'} detail={status === 'running' ? 'em execução' : 'não iniciado'} tone="orange" />
  </section>
}
