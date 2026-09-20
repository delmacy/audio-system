import { Monitor, X } from 'lucide-react'
import { useState } from 'react'
import { CwpFull } from './CwpFull'
import type { CwpConfig, ServiceConfig, SimulatorMode } from '@/features/simulator/model'

export function CwpThumb({ cwp, mode, registeredRadios, registeredTelephones, activeRadioIds, onActiveRadioIdsChange }: {
  cwp: CwpConfig
  mode: SimulatorMode
  registeredRadios?: ServiceConfig[]
  registeredTelephones?: ServiceConfig[]
  activeRadioIds?: string[]
  onActiveRadioIdsChange?: (ids: string[]) => void
}) {
  const [open, setOpen] = useState(false)
  const config = cwp[mode]
  const radios = config.services.filter(service => service.kind === 'RADIO')
  const telephones = config.services.filter(service => service.kind === 'TEL')

  return <>
    <button type="button" className="rep-cwp-thumb rep-cwp-thumb-trigger" onClick={() => setOpen(true)}>
      <span className="rep-thumb-icon"><Monitor size={22} /></span>
      <strong>{cwp.label}</strong>
      <small className="rep-cwp-thumb-ip">{config.consoleIp}</small>
      <small>Lado {cwp.side} · {radios.length} rádios · {telephones.length} TEL</small>
      <span><i className="status-dot" />Online</span>
    </button>

    {open && <div className="rep-modal-backdrop" role="presentation" onMouseDown={() => setOpen(false)}>
      <section className="rep-cwp-modal rep-cwp-operation-modal" role="dialog" aria-modal="true" aria-label={'Operar ' + cwp.label} onMouseDown={event => event.stopPropagation()}>
        <header>
          <div><span>Operação</span><strong>{cwp.label}</strong><small>{config.consoleIp}</small></div>
          <button type="button" onClick={() => setOpen(false)} aria-label="Fechar"><X size={18} /></button>
        </header>
        <CwpFull cwp={cwp} mode={mode} expanded collapsible={false} showConfigActions={false}
          registeredRadios={registeredRadios} registeredTelephones={registeredTelephones}
          activeRadioIds={activeRadioIds} onActiveRadioIdsChange={onActiveRadioIdsChange} />
      </section>
    </div>}
  </>
}
