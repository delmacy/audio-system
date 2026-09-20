import { ChevronDown, ChevronRight, Monitor, Phone, Radio, X } from 'lucide-react'
import { useState } from 'react'
import { CwpFull } from './CwpFull'
import type { CwpConfig, SimulatorMode } from '@/features/simulator/model'

export function CwpThumb({ cwp, mode }: {
  cwp: CwpConfig
  mode: SimulatorMode
}) {
  const [detailsOpen, setDetailsOpen] = useState(false)
  const [operatorOpen, setOperatorOpen] = useState(false)
  const config = cwp[mode]
  const radios = config.services.filter(service => service.kind === 'RADIO')
  const telephones = config.services.filter(service => service.kind === 'TEL')

  return <>
    <article className={'rep-cwp-thumb rep-cwp-thumb-operational' + (detailsOpen ? ' expanded' : '')}>
      <button type="button" className="rep-cwp-thumb-head" onClick={() => setDetailsOpen(value => !value)} aria-expanded={detailsOpen}>
        <span className="rep-thumb-icon"><Monitor size={22} /></span>
        <span className="rep-cwp-thumb-copy">
          <strong>{cwp.label}</strong>
          <small>Lado {cwp.side} · {radios.length} rádios · {telephones.length} TEL</small>
          <span><i className="status-dot" />Online</span>
        </span>
        <ChevronDown size={17} className={detailsOpen ? 'open' : ''} />
      </button>

      {detailsOpen && <div className="rep-cwp-thumb-details">
        <div className="rep-cwp-thumb-service-group">
          <b><Radio size={14} />Frequências ativas</b>
          {radios.map(radio => <span key={radio.id}>{radio.label}</span>)}
        </div>
        <div className="rep-cwp-thumb-service-group">
          <b><Phone size={14} />Telefones</b>
          {telephones.map(telephone => <span key={telephone.id}>{telephone.label}</span>)}
        </div>
        <button type="button" className="rep-cwp-operate-button" onClick={() => setOperatorOpen(true)}>
          Operar CWP <ChevronRight size={15} />
        </button>
      </div>}
    </article>

    {operatorOpen && <div className="rep-modal-backdrop" role="presentation" onMouseDown={() => setOperatorOpen(false)}>
      <section className="rep-cwp-modal" role="dialog" aria-modal="true" aria-label={`Operar ${cwp.label}`} onMouseDown={event => event.stopPropagation()}>
        <header>
          <div><span>Operação</span><strong>{cwp.label}</strong></div>
          <button type="button" onClick={() => setOperatorOpen(false)} aria-label="Fechar"><X size={18} /></button>
        </header>
        <CwpFull cwp={cwp} mode={mode} expanded collapsible={false} showConfigActions={false} />
      </section>
    </div>}
  </>
}
