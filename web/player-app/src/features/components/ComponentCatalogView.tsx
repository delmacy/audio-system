import { useState } from 'react'
import { Activity, ClipboardList, Database, Radio } from 'lucide-react'
import { CwpFull, CwpListItem, CwpSummary, CwpThumb, CwpThumbEdit } from '@/representations/cwp'
import { RadioFull, RadioSummary, RadioThumb, RadioThumbEdit } from '@/representations/radio'
import { TelephoneFull, TelephoneSummary, TelephoneThumb, TelephoneThumbEdit } from '@/representations/telephone'
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
  const cwpFull = { ...sample, label: 'CWP_full' }
  const cwpSummary = { ...sample, label: 'CWP_summary' }
  const cwpThumb = { ...sample, label: 'CWP_thumb' }
  const cwpThumbEdit = { ...sample, label: 'CWP_thumb_edit' }
  const cwpListItem = { ...sample, label: 'CWP_list_item' }
  const radioFull = { ...sampleRadio, label: 'RADIO_full' }
  const radioSummary = { ...sampleRadio, label: 'RADIO_summary' }
  const radioThumb = { ...sampleRadio, label: 'RADIO_thumb' }
  const radioThumbEdit = { ...sampleRadio, label: 'RADIO_thumb_edit' }
  const telephoneFull = { ...sampleTel, label: 'TELEPHONE_full' }
  const telephoneSummary = { ...sampleTel, label: 'TELEPHONE_summary' }
  const telephoneThumb = { ...sampleTel, label: 'TELEPHONE_thumb' }
  const telephoneThumbEdit = { ...sampleTel, label: 'TELEPHONE_thumb_edit' }

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
          <CwpSummary cwp={cwpSummary} mode={previewMode} />
          <div className="rep-thumb-row">
            <CwpThumb cwp={cwpThumb} mode={previewMode} />
            <CwpThumbEdit cwp={cwpThumbEdit} mode={previewMode} />
          </div>
          <CwpListItem cwp={cwpListItem} mode={previewMode} />
          <div className="catalog-isolated medium">
            <CwpFull cwp={cwpFull} mode={previewMode} expanded={expanded.includes(sample.id)}
              onToggle={() => setExpanded(expanded.includes(sample.id) ? [] : [sample.id])} />
          </div>
        </div>
      </section>

      <section className="catalog-section">
        <div className="catalog-section-title"><div><span>02</span><h2>Rádio e telefone</h2></div><p>Representações reutilizáveis fora do Simulator.</p></div>
        <div className="rep-showcase-stack">
          <div className="rep-thumb-row">
            <RadioThumb radio={radioThumb} />
            <RadioThumbEdit radio={radioThumbEdit} />
          </div>
          <RadioSummary radio={radioSummary} />
          <div className="catalog-isolated medium"><RadioFull radio={radioFull} /></div>

          <div className="rep-thumb-row">
            <TelephoneThumb telephone={telephoneThumb} />
            <TelephoneThumbEdit telephone={telephoneThumbEdit} />
          </div>
          <TelephoneSummary telephone={telephoneSummary} />
          <div className="catalog-isolated medium"><TelephoneFull telephone={telephoneFull} /></div>
        </div>
      </section>

      <section className="catalog-section">
        <div className="catalog-section-title"><div><span>03</span><h2>Recorder</h2></div><p>Status compacto, summary e visual completo.</p></div>
        <div className="rep-showcase-stack">
          <RecorderStatus displayName="RECORDER_status" />
          <RecorderSummary status={status} displayName="RECORDER_summary" />
          <div className="catalog-isolated recorder-preview"><RecorderFull mode={previewMode} status={status} displayName="RECORDER_full" /></div>
        </div>
      </section>

      <section className="catalog-section">
        <div className="catalog-section-title"><div><span>04</span><h2>Player</h2></div><p>Representações compactas para uso em listas, modais e cards.</p></div>
        <div className="rep-showcase-stack">
          <PlayerMini label="PLAYER_mini" current="01:23" duration="04:50" />
          <PlayerInline label="PLAYER_inline" />
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
