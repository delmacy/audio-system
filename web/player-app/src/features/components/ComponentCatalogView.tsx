import { useState } from 'react'
import { Activity, ClipboardList, Database, Radio } from 'lucide-react'
import { CwpFull, CwpListItem, CwpSummary, CwpThumb, CwpThumbEdit } from '@/representations/cwp'
import { RadioFull, RadioSummary, RadioThumb, RadioThumbEdit } from '@/representations/radio'
import { TelephoneDialer, TelephoneFull, TelephoneSummary, TelephoneThumb, TelephoneThumbEdit } from '@/representations/telephone'
import { RecorderFull, RecorderStatus, RecorderSummary, RecorderThumb, RecorderThumbEdit } from '@/representations/recorder'
import { SipFull, SipStatus, SipSummary, SipThumb, SipThumbEdit } from '@/representations/sip'
import { PlayerInline, PlayerMini, PlayerTrackRow, PlayerTrackSelection, PlayerTransport } from '@/representations/player'
import { ModeSwitch } from '@/features/simulator/elements/ModeSwitch'
import { SummaryCard } from '@/features/simulator/elements/SummaryCard'
import { PrimitiveCatalogSection } from '@/features/components/PrimitiveCatalogSection'
import { BlockPrimitiveCatalogSection } from '@/features/components/BlockPrimitiveCatalogSection'
import { ShadcnCatalogSection } from '@/features/components/ShadcnCatalogSection'
import { FormPrimitiveCatalogSection } from '@/features/components/FormPrimitiveCatalogSection'
import { TimelineCatalogSection } from '@/features/components/TimelineCatalogSection'
import { SIM_CWPS, type ServiceConfig, type SimStatus, type SimulatorMode } from '@/features/simulator/model'

type CatalogTab = 'cwp' | 'radios' | 'telephones' | 'recorder' | 'sip' | 'player' | 'primitives' | 'fields' | 'timeline' | 'shadcn' | 'blocks' | 'elements'

function uniqueServices(services: ServiceConfig[]) {
  const map = new Map<string, ServiceConfig>()
  services.forEach(service => {
    if (!map.has(service.label)) map.set(service.label, service)
  })
  return Array.from(map.values())
}

const CATALOG_TABS: { id: CatalogTab; label: string }[] = [
  { id: 'cwp', label: 'CWP' },
  { id: 'radios', label: 'Rádios' },
  { id: 'telephones', label: 'Telefones' },
  { id: 'recorder', label: 'Recorder' },
  { id: 'sip', label: 'SIP' },
  { id: 'player', label: 'Player' },
  { id: 'primitives', label: 'Primitivos' },
  { id: 'fields', label: 'Fields' },
  { id: 'timeline', label: 'Timeline' },
  { id: 'shadcn', label: 'shadcn/UI' },
  { id: 'blocks', label: 'Blocos' },
  { id: 'elements', label: 'Elementos' },
]

export function ComponentCatalogView({ mode, status, events: _events }: {
  mode: SimulatorMode
  status: SimStatus
  events: string[]
}) {
  const [previewMode, setPreviewMode] = useState<SimulatorMode>(mode)
  const [catalogTab, setCatalogTab] = useState<CatalogTab>('cwp')

  const sample = SIM_CWPS[0]
  const registeredRadios = uniqueServices(
    SIM_CWPS.flatMap(item => item[previewMode].services.filter(service => service.kind === 'RADIO')),
  )
  const registeredTelephones = uniqueServices(
    SIM_CWPS.flatMap(item => item[previewMode].services.filter(service => service.kind === 'TEL')),
  )
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
            <CwpThumb cwp={cwpThumb} mode={previewMode}
              registeredRadios={registeredRadios} registeredTelephones={registeredTelephones} />
            <CwpThumbEdit cwp={cwpThumbEdit} mode={previewMode} />
          </div>
          <CwpListItem cwp={cwpListItem} mode={previewMode} />
          <div className="catalog-isolated medium">
            <CwpFull cwp={cwpFull} mode={previewMode} />
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
          <div className="catalog-isolated telephone-dialer-specimen" id="telephone_dialer">
            <TelephoneDialer source={sampleTel} telephones={registeredTelephones} />
            <code>telephone_dialer</code>
          </div>
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
        <div className="catalog-section-title"><div><span>06</span><h2>Player</h2></div><p>Representações reutilizáveis de escuta e seleção de trilhas.</p></div>
        <div className="rep-showcase-stack">
          <PlayerMini label="PLAYER_mini" current="01:23" duration="04:50" />
          <PlayerInline label="PLAYER_inline" />

          <article className="catalog-isolated" id="player_track_row_selected">
            <PlayerTrackRow
              label="121500"
              group="CWP · CWP-TONE-01"
              logicalTrackUUID="c56e7dcd-5565-5f57-8a22-a5316e7a6f3e"
              mxfName="tone-multitrack.mxf"
              trackIndex={0}
              segmentCount={4}
              duration="00:01.6"
              selected
            />
            <code>player_track_row_selected</code>
          </article>

          <article className="catalog-isolated" id="player_transport_idle">
            <PlayerTransport selectedCount={2} />
            <code>player_transport_idle</code>
          </article>

          <article className="catalog-isolated" id="player_track_selection_panel">
            <PlayerTrackSelection tracks={[
              {
                label: '121500',
                group: 'CWP · CWP-TONE-01',
                logicalTrackUUID: 'c56e7dcd-5565-5f57-8a22-a5316e7a6f3e',
                mxfName: 'tone-multitrack.mxf',
                trackIndex: 0,
                segmentCount: 4,
                duration: '00:01.6',
              },
              {
                label: '118700',
                group: 'CWP · CWP-TONE-02',
                logicalTrackUUID: '0b2c1947-e74d-5329-b4a2-b1619dc7ddf7',
                mxfName: 'tone-multitrack.mxf',
                trackIndex: 1,
                segmentCount: 3,
                duration: '00:02.1',
              },
              {
                label: '050',
                group: 'TEL · TEL-TONE-01',
                logicalTrackUUID: '50704123-cd89-5099-a060-87d80b64021f',
                mxfName: 'tone-multitrack.mxf',
                trackIndex: 2,
                segmentCount: 2,
                duration: '00:02.0',
              },
            ]} />
            <code>player_track_selection_panel</code>
          </article>
        </div>
      </section>}

      {catalogTab === 'primitives' && <PrimitiveCatalogSection number="07" />}

      {catalogTab === 'fields' && <FormPrimitiveCatalogSection number="08" />}

      {catalogTab === 'timeline' && <TimelineCatalogSection number="09" />}

      {catalogTab === 'shadcn' && <ShadcnCatalogSection number="10" />}

      {catalogTab === 'blocks' && <BlockPrimitiveCatalogSection number="11" />}

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
