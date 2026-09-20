import { Network, X } from 'lucide-react'
import { useState } from 'react'
import { SipFull } from './SipFull'
import { DEMO_SIP_GATEWAY } from '@/features/sip/model'

export function SipThumb({ displayName = 'Gateway SIP' }: { displayName?: string }) {
  const [open, setOpen] = useState(false)
  const gateway = DEMO_SIP_GATEWAY

  return <>
    <button type="button" className="rep-sip-thumb" onClick={() => setOpen(true)}>
      <span className="rep-thumb-icon"><Network size={22} /></span>
      <strong>{displayName}</strong>
      <small>{gateway.ip} · SIP {gateway.port}</small>
      <span><i className="status-dot" />{gateway.activeSessions} sessões</span>
    </button>

    {open && <div className="rep-modal-backdrop" role="presentation" onMouseDown={() => setOpen(false)}>
      <section className="rep-sip-modal" role="dialog" aria-modal="true" aria-label={displayName} onMouseDown={event => event.stopPropagation()}>
        <header><div><span>Operação SIP</span><strong>{displayName}</strong></div><button type="button" onClick={() => setOpen(false)} aria-label="Fechar"><X size={18} /></button></header>
        <SipFull displayName="SIP_full" />
      </section>
    </div>}
  </>
}
