import { useState } from 'react'
import { Activity, ClipboardList, Database, Radio } from 'lucide-react'
import { CwpCard } from '@/features/simulator/components/CwpCard'
import { EventsPanel } from '@/features/simulator/components/EventsPanel'
import { ModeSwitch } from '@/features/simulator/components/ModeSwitch'
import { RecorderTopology } from '@/features/simulator/components/RecorderTopology'
import { SidePanel } from '@/features/simulator/components/SidePanel'
import { SummaryCard } from '@/features/simulator/components/SummaryCard'
import { SIM_CWPS, type SimStatus, type SimulatorMode } from '@/features/simulator/model'

export function ComponentCatalogView({ mode, status, events }: { mode: SimulatorMode; status: SimStatus; events: string[] }) {
  const [previewMode, setPreviewMode] = useState<SimulatorMode>(mode)
  const [expanded, setExpanded] = useState<string[]>(['cwp-a01'])

  return <main className="component-catalog-main">
    <header className="component-catalog-header">
      <div>
        <span className="catalog-eyebrow">Audio System · Frontend composition</span>
        <h1>Catálogo de Componentes</h1>
        <p>Os elementos abaixo são os componentes reais usados nas telas. Ajustes visuais aqui propagam para a aplicação.</p>
      </div>
      <ModeSwitch mode={previewMode} onChange={setPreviewMode} />
    </header>

    <div className="catalog-body">
      <section className="catalog-section">
        <div className="catalog-section-title"><div><span>01</span><h2>Status Cards</h2></div><p>Resumo operacional reutilizado no dashboard.</p></div>
        <div className="catalog-summary-grid">
          <SummaryCard icon={ClipboardList} title="CWP's" value="4" detail="ativos de 4" />
          <SummaryCard icon={Radio} title="Rádios" value="8" detail="ativos de 8" tone="green" />
          <SummaryCard icon={Database} title="Serviços Total" value="16" detail="ativos" tone="green" />
          <SummaryCard icon={Activity} title="Duração" value="00:30:00" detail="pronto" tone="orange" />
        </div>
      </section>

      <section className="catalog-section">
        <div className="catalog-section-title"><div><span>02</span><h2>CWP Card</h2></div><p>Unidade de console com serviços, metadados e estado expandido.</p></div>
        <div className="catalog-isolated medium">
          <CwpCard cwp={SIM_CWPS[0]} mode={previewMode} expanded={expanded.includes('cwp-a01')}
            onToggle={() => setExpanded(expanded.includes('cwp-a01') ? [] : ['cwp-a01'])} />
        </div>
      </section>

      <section className="catalog-section">
        <div className="catalog-section-title"><div><span>03</span><h2>Side-A Group</h2></div><p>Composição dos CWPs de um lado operacional.</p></div>
        <div className="catalog-isolated wide">
          <SidePanel side="A" mode={previewMode} expanded={expanded} setExpanded={setExpanded} />
        </div>
      </section>

      <section className="catalog-section">
        <div className="catalog-section-title"><div><span>04</span><h2>Recorder Card / Diagrama</h2></div><p>Topologia real do frontend: Recorder e Gateway SIP.</p></div>
        <div className="catalog-isolated recorder-preview">
          <RecorderTopology mode={previewMode} status={status} />
        </div>
      </section>

      <section className="catalog-section">
        <div className="catalog-section-title"><div><span>05</span><h2>Status lateral e eventos</h2></div><p>Live Status, console de eventos e métricas.</p></div>
        <div className="catalog-isolated events-preview">
          <EventsPanel events={events.slice(0, 6)} />
        </div>
      </section>
    </div>
  </main>
}
