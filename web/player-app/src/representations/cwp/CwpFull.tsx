import { Save } from 'lucide-react'
import { useEffect, useState } from 'react'
import type { CwpConfig, SimulatorMode } from '@/features/simulator/model'

export type CwpFullDraft = {
  label: string
  side: 'A' | 'B'
  consoleIp: string
  radios: number
  telephones: number
  notes: string
}

export function CwpFull({
  cwp,
  mode,
  onSave,
  onCancel,
}: {
  cwp: CwpConfig
  mode: SimulatorMode
  onSave?: (draft: CwpFullDraft) => void
  onCancel?: () => void
}) {
  const config = cwp[mode]
  const buildDraft = (): CwpFullDraft => ({
    label: cwp.label,
    side: cwp.side,
    consoleIp: config.consoleIp,
    radios: config.radios,
    telephones: config.telephones,
    notes: config.notes,
  })
  const [draft, setDraft] = useState<CwpFullDraft>(buildDraft)

  useEffect(() => {
    setDraft({
      label: cwp.label,
      side: cwp.side,
      consoleIp: cwp[mode].consoleIp,
      radios: cwp[mode].radios,
      telephones: cwp[mode].telephones,
      notes: cwp[mode].notes,
    })
  }, [cwp, mode])

  const radios = config.services.filter(service => service.kind === 'RADIO')
  const telephones = config.services.filter(service => service.kind === 'TEL')

  return <section className="cwp-full-config" id="cwp_full">
    <div className="cwp-full-grid">
      <label>Nome<input value={draft.label} onChange={event => setDraft({ ...draft, label: event.target.value })} /></label>
      <label>Lado<select value={draft.side} onChange={event => setDraft({ ...draft, side: event.target.value as 'A' | 'B' })}>
        <option value="A">A</option><option value="B">B</option>
      </select></label>
      <label className="wide">Console IP<input value={draft.consoleIp} onChange={event => setDraft({ ...draft, consoleIp: event.target.value })} /></label>
      <label>Rádios configurados<input type="number" min="0" value={draft.radios} onChange={event => setDraft({ ...draft, radios: Number(event.target.value) })} /></label>
      <label>Telefones configurados<input type="number" min="0" value={draft.telephones} onChange={event => setDraft({ ...draft, telephones: Number(event.target.value) })} /></label>
      <label className="wide">Observações<textarea value={draft.notes} onChange={event => setDraft({ ...draft, notes: event.target.value })} /></label>
    </div>

    <div className="cwp-full-services">
      <section>
        <header><strong>Rádios do CWP</strong><span>{radios.length}</span></header>
        <div>{radios.map(service => <article key={service.id}><strong>{service.label}</strong><code>{service.endpoint}</code></article>)}</div>
      </section>
      <section>
        <header><strong>Ramais do CWP</strong><span>{telephones.length}</span></header>
        <div>{telephones.map(service => <article key={service.id}><strong>{service.label}</strong><code>{service.endpoint}</code></article>)}</div>
      </section>
    </div>

    {(onSave || onCancel) && <footer className="cwp-full-actions">
      {onCancel && <button type="button" onClick={onCancel}>Cancelar</button>}
      {onSave && <button type="button" className="rep-cwp-save-button" onClick={() => onSave(draft)}><Save size={15} />Salvar configuração</button>}
    </footer>}
  </section>
}
