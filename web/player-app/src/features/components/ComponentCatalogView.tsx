import { useState } from 'react'
import { Activity, ClipboardList, Database, Radio } from 'lucide-react'
import { CwpCard } from '@/features/simulator/blocks/CwpCard'
import { EventsBlock } from '@/features/simulator/blocks/EventsBlock'
import { RecorderTopologyBlock } from '@/features/simulator/blocks/RecorderTopologyBlock'
import { SideBlock } from '@/features/simulator/blocks/SideBlock'
import { ModeSwitch } from '@/features/simulator/elements/ModeSwitch'
import { SummaryCard } from '@/features/simulator/elements/SummaryCard'
import { SIM_CWPS, type SimStatus, type SimulatorMode } from '@/features/simulator/model'

export function ComponentCatalogView({ mode, status, events }: {
  mode: SimulatorMode
  status: SimStatus
  events: string[]
}) {
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
        <div className="catalog-section-title"><div><span>01</span><h2>Elementos · Status Cards</h2></div><p>Peças unitárias reutilizadas dentro dos blocos.</p></div>
        <div className="catalog-summary-grid">
          <SummaryCard icon={ClipboardList} title="CWP's" value="4" detail="ativos de 4" />
          <SummaryCard icon={Radio} title="Rádios" value="8" detail="ativos de 8" tone="green" />
          <SummaryCard icon={Database} title="Serviços Total" value="16" detail="ativos" tone="green" />
          <SummaryCard icon={Activity} title="Duração" value="00:30:00" detail="pronto" tone="orange" />
        </div>
      </section>

      <section className="catalog-section">
        <div className="catalog-section-title"><div><span>02</span><h2>Bloco · CWP Card</h2></div><p>Compõe listas de rádio e telefone.</p></div>
        <div className="catalog-isolated medium">
          <CwpCard cwp={SIM_CWPS[0]} mode={previewMode} expanded={expanded.includes('cwp-a01')}
            onToggle={() => setExpanded(expanded.includes('cwp-a01') ? [] : ['cwp-a01'])} />
        </div>
      </section>

      <section className="catalog-section">
        <div className="catalog-section-title"><div><span>03</span><h2>Bloco · Side A</h2></div><p>Compõe a lista de CWPs de um lado operacional.</p></div>
        <div className="catalog-isolated wide">
          <SideBlock side="A" mode={previewMode} expanded={expanded} setExpanded={setExpanded} />
        </div>
      </section>

      <section className="catalog-section">
        <div className="catalog-section-title"><div><span>04</span><h2>Bloco · Recorder</h2></div><p>Topologia real do frontend: Recorder e Gateway SIP.</p></div>
        <div className="catalog-isolated recorder-preview">
          <RecorderTopologyBlock mode={previewMode} status={status} />
        </div>
      </section>

      <section className="catalog-section">
        <div className="catalog-section-title"><div><span>05</span><h2>Bloco · Status e eventos</h2></div><p>Live Status, console de eventos e métricas.</p></div>
        <div className="catalog-isolated events-preview">
          <EventsBlock events={events.slice(0, 6)} />
        </div>
      </section>
    </div>
  </main>
}
