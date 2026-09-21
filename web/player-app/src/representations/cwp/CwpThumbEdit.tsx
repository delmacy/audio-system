import { Monitor, Save, X } from 'lucide-react'
import { useEffect, useState } from 'react'
import type { CwpConfig, SimulatorMode } from '@/features/simulator/model'

export type CwpThumbEditDraft = {
  label: string
  side: 'A' | 'B'
  consoleIp: string
  radios: number
  telephones: number
  notes: string
}

export function CwpThumbEdit({ cwp, mode, onSave }: {
  cwp: CwpConfig
  mode: SimulatorMode
  onSave?: (draft: CwpThumbEditDraft) => void
}) {
  const [open, setOpen] = useState(false)
  const config = cwp[mode]
  const buildDraft = (): CwpThumbEditDraft => ({
    label: cwp.label,
    side: cwp.side,
    consoleIp: config.consoleIp,
    radios: config.radios,
    telephones: config.telephones,
    notes: config.notes,
  })
  const [draft, setDraft] = useState<CwpThumbEditDraft>(buildDraft)

  useEffect(() => setDraft(buildDraft()), [cwp, mode])

  const save = () => {
    onSave?.(draft)
    setOpen(false)
  }

  return <>
    <button type="button" className="rep-cwp-thumb rep-cwp-thumb-trigger rep-cwp-thumb-edit-trigger" onClick={() => setOpen(true)}>
      <span className="rep-thumb-icon edit"><Monitor size={22} /></span>
      <strong>{cwp.label}</strong>
      <small className="rep-cwp-thumb-ip">IP {config.consoleIp}</small>
      <small>Configuração · não operacional</small>
      <span>Editar campos</span>
    </button>

    {open && <div className="rep-modal-backdrop" role="presentation" onMouseDown={() => setOpen(false)}>
      <section className="rep-cwp-modal rep-cwp-edit-modal" role="dialog" aria-modal="true" aria-label={`Editar ${cwp.label}`} onMouseDown={event => event.stopPropagation()}>
        <header>
          <div><span>Configuração</span><strong>{cwp.label}</strong></div>
          <button type="button" onClick={() => setOpen(false)} aria-label="Fechar"><X size={18} /></button>
        </header>

        <div className="rep-cwp-edit-grid">
          <label>Nome<input value={draft.label} onChange={event => setDraft({ ...draft, label: event.target.value })} /></label>
          <label>Lado<select value={draft.side} onChange={event => setDraft({ ...draft, side: event.target.value as 'A' | 'B' })}><option value="A">A</option><option value="B">B</option></select></label>
          <label className="wide">Console IP<input value={draft.consoleIp} onChange={event => setDraft({ ...draft, consoleIp: event.target.value })} /></label>
          <label>Rádios<input type="number" min="0" value={draft.radios} onChange={event => setDraft({ ...draft, radios: Number(event.target.value) })} /></label>
          <label>Telefones<input type="number" min="0" value={draft.telephones} onChange={event => setDraft({ ...draft, telephones: Number(event.target.value) })} /></label>
          <label className="wide">Observações<textarea value={draft.notes} onChange={event => setDraft({ ...draft, notes: event.target.value })} /></label>
        </div>

        <div className="rep-cwp-edit-actions">
          <button type="button" onClick={() => setOpen(false)}>Cancelar</button>
          <button type="button" className="rep-cwp-save-button" onClick={save}><Save size={15} />Salvar configuração</button>
        </div>
      </section>
    </div>}
  </>
}
