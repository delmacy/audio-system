import { Network, Save, X } from 'lucide-react'
import { useState } from 'react'
import { DEMO_SIP_GATEWAY, type SipGatewayConfig } from '@/features/sip/model'

export function SipThumbEdit({ displayName = 'Gateway SIP edit', onSave }: {
  displayName?: string
  onSave?: (config: SipGatewayConfig) => void
}) {
  const [open, setOpen] = useState(false)
  const [draft, setDraft] = useState<SipGatewayConfig>(DEMO_SIP_GATEWAY)

  return <>
    <button type="button" className="rep-sip-thumb edit" onClick={() => setOpen(true)}>
      <span className="rep-thumb-icon edit"><Network size={22} /></span>
      <strong>{displayName}</strong>
      <small>Configuração · não operacional</small>
      <span>Editar gateway</span>
    </button>

    {open && <div className="rep-modal-backdrop" role="presentation" onMouseDown={() => setOpen(false)}>
      <section className="rep-sip-modal" role="dialog" aria-modal="true" aria-label={displayName} onMouseDown={event => event.stopPropagation()}>
        <header><div><span>Configuração SIP</span><strong>{displayName}</strong></div><button type="button" onClick={() => setOpen(false)} aria-label="Fechar"><X size={18} /></button></header>
        <div className="rep-sip-edit-grid">
          <label>Nome<input value={draft.name} onChange={e => setDraft({ ...draft, name: e.target.value })} /></label>
          <label>IP<input value={draft.ip} onChange={e => setDraft({ ...draft, ip: e.target.value })} /></label>
          <label>Porta SIP<input type="number" value={draft.port} onChange={e => setDraft({ ...draft, port: Number(e.target.value) })} /></label>
          <label>Transporte<select value={draft.transport} onChange={e => setDraft({ ...draft, transport: e.target.value as SipGatewayConfig['transport'] })}><option>UDP</option><option>TCP</option><option>TLS</option></select></label>
          <label>Registrar<input value={draft.registrar} onChange={e => setDraft({ ...draft, registrar: e.target.value })} /></label>
          <label>Destino de mídia<input value={draft.mediaTarget} onChange={e => setDraft({ ...draft, mediaTarget: e.target.value })} /></label>
        </div>
        <div className="rep-cwp-edit-actions">
          <button type="button" onClick={() => setOpen(false)}>Cancelar</button>
          <button type="button" className="rep-cwp-save-button" onClick={() => { onSave?.(draft); setOpen(false) }}><Save size={15} />Salvar configuração</button>
        </div>
      </section>
    </div>}
  </>
}
