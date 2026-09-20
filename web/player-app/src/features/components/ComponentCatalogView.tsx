import { useState } from 'react'
import { Activity, ClipboardList, Database, Radio } from 'lucide-react'
import { CwpFull, CwpListItem, CwpSummary, CwpThumb } from '@/representations/cwp'
import { RadioSummary } from '@/representations/radio'
import { TelephoneSummary } from '@/representations/telephone'
import { RecorderFull, RecorderStatus, RecorderSummary } from '@/representations/recorder'
import { PlayerInline, PlayerMini } from '@/representations/player'
import { EventsBlock } from '@/features/simulator/blocks/EventsBlock'
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
  const sample = SIM_CWPS[0]
  const sampleRadio = sample[previewMode].services.find(service => service.kind === 'RADIO')!
  const sampleTel = sample[previewMode].services.find(service => service.kind === 'TEL')!

  return <main className="component-catalog-main">
    <header className="component-catalog-header">
      <div>
        <span className="catalog-eyebrow">Audio System · visual representations</span>
        <h1>Catálogo de Representações</h1>
        <p>A mesma entidade pode ser Full, Summary, Thumb ou ListItem conforme a densidade exigida pela view.</p>
      </div>
      <ModeSwitch mode={previewMode} onChange={setPreviewMode} />
    </header>

    <div className="catalog-body">
      <section className="catalog-section">
        <div className="catalog-section-title"><div><span>01</span><h2>CWP · múltiplas representações</h2></div><p>Uma entidade, várias densidades visuais.</p></div>
        <div className="rep-showcase-stack">
          <CwpSummary cwp={sample} mode={previewMode} />
          <div className="rep-thumb-row"><CwpThumb cwp={sample} mode={previewMode} /><CwpThumb cwp={SIM_CWPS[1]} mode={previewMode} /></div>
          <CwpListItem cwp={sample} mode={previewMode} />
          <div className="catalog-isolated medium">
            <CwpFull cwp={sample} mode={previewMode} expanded={expanded.includes(sample.id)}
              onToggle={() => setExpanded(expanded.includes(sample.id) ? [] : [sample.id])} />
          </div>
        </div>
      </section>

      <section className="catalog-section">
        <div className="catalog-section-title"><div><span>02</span><h2>Rádio e telefone</h2></div><p>Representações reutilizáveis fora do Simulator.</p></div>
        <div className="rep-showcase-stack">
          <RadioSummary radio={sampleRadio} />
          <TelephoneSummary telephone={sampleTel} />
        </div>
      </section>

      <section className="catalog-section">
        <div className="catalog-section-title"><div><span>03</span><h2>Recorder</h2></div><p>Status compacto, summary e visual completo.</p></div>
        <div className="rep-showcase-stack">
          <RecorderStatus />
          <RecorderSummary status={status} />
          <div className="catalog-isolated recorder-preview"><RecorderFull mode={previewMode} status={status} /></div>
        </div>
      </section>

      <section className="catalog-section">
        <div className="catalog-section-title"><div><span>04</span><h2>Player</h2></div><p>Representações compactas para uso em listas, modais e cards.</p></div>
        <div className="rep-showcase-stack">
          <PlayerMini current="01:23" duration="04:50" />
          <PlayerInline label="TWR 121.500 · gravação selecionada" />
        </div>
      </section>

      <section className="catalog-section">
        <div className="catalog-section-title"><div><span>05</span><h2>Blocos compostos</h2></div><p>As features montam representações conforme a necessidade.</p></div>
        <div className="catalog-isolated wide"><SideBlock side="A" mode={previewMode} expanded={expanded} setExpanded={setExpanded} /></div>
        <div className="catalog-isolated events-preview"><EventsBlock events={events.slice(0, 6)} /></div>
      </section>

      <section className="catalog-section">
        <div className="catalog-section-title"><div><span>06</span><h2>Elementos genéricos</h2></div><p>Peças não vinculadas a uma entidade específica.</p></div>
        <div className="catalog-summary-grid">
          <SummaryCard icon={ClipboardList} title="CWP's" value="4" detail="ativos de 4" />
          <SummaryCard icon={Radio} title="Rádios" value="8" detail="ativos de 8" tone="green" />
          <SummaryCard icon={Database} title="Serviços Total" value="16" detail="ativos" tone="green" />
          <SummaryCard icon={Activity} title="Duração" value="00:30:00" detail="pronto" tone="orange" />
        </div>
      </section>
    </div>
  </main>
}
