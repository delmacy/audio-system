import { Phone, Save, X } from 'lucide-react'
import { useEffect, useState } from 'react'
import type { ServiceConfig } from '@/features/simulator/model'

export type TelephoneThumbEditDraft = Pick<ServiceConfig, 'label' | 'endpoint' | 'status'>

export function TelephoneThumbEdit({ telephone, onSave }: { telephone: ServiceConfig; onSave?: (draft: TelephoneThumbEditDraft) => void }) {
  const [open, setOpen] = useState(false)
  const [draft, setDraft] = useState<TelephoneThumbEditDraft>({ label: telephone.label, endpoint: telephone.endpoint, status: telephone.status })

  useEffect(() => setDraft({ label: telephone.label, endpoint: telephone.endpoint, status: telephone.status }), [telephone])

  return <>
    <button type="button" className="rep-service-thumb tel edit" onClick={() => setOpen(true)}>
      <span className="rep-thumb-icon edit"><Phone size={22} /></span>
      <strong>{telephone.label}</strong><small>Configuração · não operacional</small><span>Editar campos</span>
    </button>

    {open && <div className="rep-modal-backdrop" role="presentation" onMouseDown={() => setOpen(false)}>
      <section className="rep-service-modal" role="dialog" aria-modal="true" aria-label={`Editar ${telephone.label}`} onMouseDown={event => event.stopPropagation()}>
        <header><div><span>Configuração de telefone</span><strong>{telephone.label}</strong></div><button type="button" onClick={() => setOpen(false)} aria-label="Fechar"><X size={18} /></button></header>
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
