import { Monitor, Save } from 'lucide-react'
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

  return <article className="rep-cwp-thumb rep-cwp-thumb-edit">
    <div className="rep-cwp-thumb-edit-head">
      <span className="rep-thumb-icon edit"><Monitor size={22} /></span>
      <div><strong>{draft.label}</strong><small>Configuração · não operacional</small></div>
    </div>

    <div className="rep-cwp-edit-grid">
      <label>Nome<input value={draft.label} onChange={event => setDraft({ ...draft, label: event.target.value })} /></label>
      <label>Lado<select value={draft.side} onChange={event => setDraft({ ...draft, side: event.target.value as 'A' | 'B' })}><option value="A">A</option><option value="B">B</option></select></label>
      <label className="wide">Console IP<input value={draft.consoleIp} onChange={event => setDraft({ ...draft, consoleIp: event.target.value })} /></label>
      <label>Rádios<input type="number" min="0" value={draft.radios} onChange={event => setDraft({ ...draft, radios: Number(event.target.value) })} /></label>
      <label>Telefones<input type="number" min="0" value={draft.telephones} onChange={event => setDraft({ ...draft, telephones: Number(event.target.value) })} /></label>
      <label className="wide">Observações<textarea value={draft.notes} onChange={event => setDraft({ ...draft, notes: event.target.value })} /></label>
    </div>

    <button type="button" className="rep-cwp-save-button" onClick={() => onSave?.(draft)}>
      <Save size={15} />Salvar configuração
    </button>
  </article>
}
