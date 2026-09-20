import { Radio, Save, X } from 'lucide-react'
import { useEffect, useState } from 'react'
import type { ServiceConfig } from '@/features/simulator/model'

export type RadioThumbEditDraft = Pick<ServiceConfig, 'label' | 'endpoint' | 'status'>

export function RadioThumbEdit({ radio, onSave }: { radio: ServiceConfig; onSave?: (draft: RadioThumbEditDraft) => void }) {
  const [open, setOpen] = useState(false)
  const [draft, setDraft] = useState<RadioThumbEditDraft>({ label: radio.label, endpoint: radio.endpoint, status: radio.status })

  useEffect(() => setDraft({ label: radio.label, endpoint: radio.endpoint, status: radio.status }), [radio])

  return <>
    <button type="button" className="rep-service-thumb radio edit" onClick={() => setOpen(true)}>
      <span className="rep-thumb-icon edit"><Radio size={22} /></span>
      <strong>{radio.label}</strong><small>Configuração · não operacional</small><span>Editar campos</span>
    </button>

    {open && <div className="rep-modal-backdrop" role="presentation" onMouseDown={() => setOpen(false)}>
      <section className="rep-service-modal" role="dialog" aria-modal="true" aria-label={`Editar ${radio.label}`} onMouseDown={event => event.stopPropagation()}>
        <header><div><span>Configuração de rádio</span><strong>{radio.label}</strong></div><button type="button" onClick={() => setOpen(false)} aria-label="Fechar"><X size={18} /></button></header>
        <div className="rep-service-edit-grid">
          <label>Nome<input value={draft.label} onChange={event => setDraft({ ...draft, label: event.target.value })} /></label>
          <label>Status<select value={draft.status} onChange={event => setDraft({ ...draft, status: event.target.value as 'active' | 'idle' })}><option value="active">Ativo</option><option value="idle">Inativo</option></select></label>
          <label className="wide">Endpoint<input value={draft.endpoint} onChange={event => setDraft({ ...draft, endpoint: event.target.value })} /></label>
        </div>
        <div className="rep-cwp-edit-actions"><button type="button" onClick={() => setOpen(false)}>Cancelar</button><button type="button" className="rep-cwp-save-button" onClick={() => { onSave?.(draft); setOpen(false) }}><Save size={15} />Salvar configuração</button></div>
      </section>
    </div>}
  </>
}
