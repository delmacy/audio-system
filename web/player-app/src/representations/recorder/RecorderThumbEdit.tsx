import { Save, Server, X } from 'lucide-react'
import { useState } from 'react'
import { DEMO_RECORDER, type RecorderConfig } from '@/features/recorder/model'

export function RecorderThumbEdit({ displayName = 'Recorder edit', onSave }: {
  displayName?: string
  onSave?: (config: RecorderConfig) => void
}) {
  const [open, setOpen] = useState(false)
  const [draft, setDraft] = useState<RecorderConfig>(DEMO_RECORDER)

  return <>
    <button type="button" className="rep-recorder-thumb edit" onClick={() => setOpen(true)}>
      <span className="rep-thumb-icon edit"><Server size={22} /></span>
      <strong>{displayName}</strong>
      <small>Configuração · não operacional</small>
      <span>Editar gravador</span>
    </button>

    {open && <div className="rep-modal-backdrop" role="presentation" onMouseDown={() => setOpen(false)}>
      <section className="rep-recorder-modal" role="dialog" aria-modal="true" aria-label={displayName} onMouseDown={event => event.stopPropagation()}>
        <header><div><span>Configuração do gravador</span><strong>{displayName}</strong></div><button type="button" onClick={() => setOpen(false)} aria-label="Fechar"><X size={18} /></button></header>
        <div className="rep-recorder-edit-grid">
          <label>Nome<input value={draft.name} onChange={e => setDraft({ ...draft, name: e.target.value })} /></label>
          <label>IP<input value={draft.ip} onChange={e => setDraft({ ...draft, ip: e.target.value })} /></label>
          <label>RTSP<input type="number" value={draft.rtspPort} onChange={e => setDraft({ ...draft, rtspPort: Number(e.target.value) })} /></label>
          <label>Split (min)<input type="number" value={draft.splitMinutes} onChange={e => setDraft({ ...draft, splitMinutes: Number(e.target.value) })} /></label>
          <label>Writer<input value={draft.writer} onChange={e => setDraft({ ...draft, writer: e.target.value })} /></label>
          <label>Codec<input value={draft.codec} onChange={e => setDraft({ ...draft, codec: e.target.value })} /></label>
        </div>
        <div className="rep-cwp-edit-actions">
          <button type="button" onClick={() => setOpen(false)}>Cancelar</button>
          <button type="button" className="rep-cwp-save-button" onClick={() => { onSave?.(draft); setOpen(false) }}><Save size={15} />Salvar configuração</button>
        </div>
      </section>
    </div>}
  </>
}
