import { useState } from 'react'
import { Activity, ClipboardList, Database, Radio } from 'lucide-react'
import { CwpFull, CwpListItem, CwpSummary, CwpThumb, CwpThumbEdit } from '@/representations/cwp'
import { RadioFull, RadioSummary, RadioThumb, RadioThumbEdit } from '@/representations/radio'
import { TelephoneFull, TelephoneSummary, TelephoneThumb, TelephoneThumbEdit } from '@/representations/telephone'
import { RecorderFull, RecorderStatus, RecorderSummary, RecorderThumb, RecorderThumbEdit } from '@/representations/recorder'
import { SipFull, SipStatus, SipSummary, SipThumb, SipThumbEdit } from '@/representations/sip'
import { PlayerInline, PlayerMini } from '@/representations/player'
import { ModeSwitch } from '@/features/simulator/elements/ModeSwitch'
import { SummaryCard } from '@/features/simulator/elements/SummaryCard'
import { PrimitiveCatalogSection } from '@/features/components/PrimitiveCatalogSection'
import { ShadcnCatalogSection } from '@/features/components/ShadcnCatalogSection'
import { SIM_CWPS, type SimStatus, type SimulatorMode } from '@/features/simulator/model'

type CatalogTab = 'cwp' | 'radios' | 'telephones' | 'recorder' | 'sip' | 'player' | 'primitives' | 'shadcn' | 'blocks' | 'elements'

const CATALOG_TABS: { id: CatalogTab; label: string }[] = [
  { id: 'cwp', label: 'CWP' },
  { id: 'radios', label: 'Rádios' },
  { id: 'telephones', label: 'Telefones' },
  { id: 'recorder', label: 'Recorder' },
  { id: 'sip', label: 'SIP' },
  { id: 'player', label: 'Player' },
  { id: 'primitives', label: 'Primitivos' },
  { id: 'shadcn', label: 'shadcn/UI' },
  { id: 'blocks', label: 'Blocos' },
  { id: 'elements', label: 'Elementos' },
]

export function ComponentCatalogView({ mode, status, events }: {
  mode: SimulatorMode
  status: SimStatus
  events: string[]
}) {
  const [previewMode, setPreviewMode] = useState<SimulatorMode>(mode)
  const [expanded, setExpanded] = useState<string[]>(['cwp-a01'])
  const [catalogTab, setCatalogTab] = useState<CatalogTab>('cwp')

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
        <p>Entidades, blocos e primitivos isolados para composição e refinamento visual.</p>
      </div>
      <ModeSwitch mode={previewMode} onChange={setPreviewMode} />
    </header>

    <nav className="catalog-primary-tabs" aria-label="Famílias de componentes">
      {CATALOG_TABS.map(tab => <button
        type="button"
        key={tab.id}
        className={catalogTab === tab.id ? 'active' : ''}
        onClick={() => setCatalogTab(tab.id)}
      >{tab.label}</button>)}
    </nav>

    <div className="catalog-body">
      {catalogTab === 'cwp' && <section className="catalog-section">
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
      </section>}

      {catalogTab === 'radios' && <section className="catalog-section">
        <div className="catalog-section-title"><div><span>02</span><h2>Rádios</h2></div><p>Representações operacionais e editáveis da entidade rádio.</p></div>
        <div className="rep-showcase-stack">
          <div className="rep-thumb-row">
            <RadioThumb radio={radioThumb} />
            <RadioThumbEdit radio={radioThumbEdit} />
          </div>
          <RadioSummary radio={radioSummary} />
          <div className="catalog-isolated medium"><RadioFull radio={radioFull} /></div>
        </div>
      </section>}

      {catalogTab === 'telephones' && <section className="catalog-section">
        <div className="catalog-section-title"><div><span>03</span><h2>Telefones</h2></div><p>Representações operacionais e editáveis da entidade telefone.</p></div>
        <div className="rep-showcase-stack">
          <div className="rep-thumb-row">
            <TelephoneThumb telephone={telephoneThumb} />
            <TelephoneThumbEdit telephone={telephoneThumbEdit} />
          </div>
          <TelephoneSummary telephone={telephoneSummary} />
          <div className="catalog-isolated medium"><TelephoneFull telephone={telephoneFull} /></div>
        </div>
      </section>}

      {catalogTab === 'recorder' && <section className="catalog-section">
        <div className="catalog-section-title"><div><span>04</span><h2>Recorder</h2></div><p>Core de gravação em múltiplas densidades.</p></div>
        <div className="rep-showcase-stack">
          <div className="rep-thumb-row">
            <RecorderThumb status={status} displayName="RECORDER_thumb" />
            <RecorderThumbEdit displayName="RECORDER_thumb_edit" />
          </div>
          <RecorderStatus displayName="RECORDER_status" />
          <RecorderSummary status={status} displayName="RECORDER_summary" />
          <div className="catalog-isolated recorder-preview"><RecorderFull mode={previewMode} status={status} displayName="RECORDER_full" /></div>
        </div>
      </section>}

      {catalogTab === 'sip' && <section className="catalog-section">
        <div className="catalog-section-title"><div><span>05</span><h2>Gateway SIP</h2></div><p>Entidade própria de sinalização e tradução.</p></div>
        <div className="rep-showcase-stack">
          <div className="rep-thumb-row">
            <SipThumb displayName="SIP_thumb" />
            <SipThumbEdit displayName="SIP_thumb_edit" />
          </div>
          <SipStatus displayName="SIP_status" />
          <SipSummary displayName="SIP_summary" />
          <div className="catalog-isolated medium"><SipFull displayName="SIP_full" /></div>
        </div>
      </section>}

      {catalogTab === 'player' && <section className="catalog-section">
        <div className="catalog-section-title"><div><span>06</span><h2>Player</h2></div><p>Representações compactas reutilizáveis.</p></div>
        <div className="rep-showcase-stack">
          <PlayerMini label="PLAYER_mini" current="01:23" duration="04:50" />
          <PlayerInline label="PLAYER_inline" />
        </div>
      </section>}

      {catalogTab === 'primitives' && <PrimitiveCatalogSection number="07" />}

      {catalogTab === 'shadcn' && <ShadcnCatalogSection number="08" />}

      {catalogTab === 'blocks' && <section className="catalog-section">
        <div className="catalog-section-title"><div><span>09</span><h2>Blocos compostos</h2></div><p>Reservado para composições futuras.</p></div>
        <div className="catalog-empty-state">Nenhum bloco composto catalogado ainda.</div>
      </section>}

      {catalogTab === 'elements' && <section className="catalog-section">
        <div className="catalog-section-title"><div><span>11</span><h2>Elementos genéricos</h2></div><p>Peças não vinculadas a uma entidade específica.</p></div>
        <div className="catalog-summary-grid">
          <SummaryCard icon={ClipboardList} title="CWP's" value="4" detail="ativos de 4" />
          <SummaryCard icon={Radio} title="Rádios" value="8" detail="ativos de 8" tone="green" />
          <SummaryCard icon={Database} title="Serviços Total" value="16" detail="ativos" tone="green" />
          <SummaryCard icon={Activity} title="Duração" value="00:30:00" detail="pronto" tone="orange" />
        </div>
      </section>}
    </div>
  </main>
}
