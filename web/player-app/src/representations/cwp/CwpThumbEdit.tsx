import { Monitor, X } from 'lucide-react'
import { useState } from 'react'
import { CwpFull, type CwpFullDraft } from './CwpFull'
import type { CwpConfig, SimulatorMode } from '@/features/simulator/model'

export type CwpThumbEditDraft = CwpFullDraft

export function CwpThumbEdit({ cwp, mode, onSave }: {
  cwp: CwpConfig
  mode: SimulatorMode
  onSave?: (draft: CwpThumbEditDraft) => void
}) {
  const [open, setOpen] = useState(false)
  const config = cwp[mode]

  const save = (draft: CwpFullDraft) => {
    onSave?.(draft)
    setOpen(false)
  }

  return <>
    <button type="button" className="rep-cwp-thumb rep-cwp-thumb-trigger rep-cwp-thumb-edit-trigger" onClick={() => setOpen(true)}>
      <span className="rep-thumb-icon edit"><Monitor size={22} /></span>
      <strong>{cwp.label}</strong>
      <small className="rep-cwp-thumb-ip">IP {config.consoleIp}</small>
      <small>Configuração · não operacional</small>
      <span>Editar CWP</span>
    </button>

    {open && <div className="rep-modal-backdrop" role="presentation" onMouseDown={() => setOpen(false)}>
      <section className="rep-cwp-modal rep-cwp-edit-modal rep-cwp-full-modal" role="dialog" aria-modal="true" aria-label={'Editar ' + cwp.label} onMouseDown={event => event.stopPropagation()}>
        <header>
          <div><span>CWP_full</span><strong>{cwp.label}</strong></div>
          <button type="button" onClick={() => setOpen(false)} aria-label="Fechar"><X size={18} /></button>
        </header>
        <CwpFull cwp={cwp} mode={mode} onSave={save} onCancel={() => setOpen(false)} />
      </section>
    </div>}
  </>
}
