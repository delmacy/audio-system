import { Phone, X } from 'lucide-react'
import { useState } from 'react'
import { TelephoneFull } from './TelephoneFull'
import type { ServiceConfig } from '@/features/simulator/model'

export function TelephoneThumb({ telephone }: { telephone: ServiceConfig }) {
  const [open, setOpen] = useState(false)

  return <>
    <button type="button" className="rep-service-thumb tel" onClick={() => setOpen(true)}>
      <span className="rep-thumb-icon"><Phone size={22} /></span>
      <strong>{telephone.label}</strong>
      <small>{telephone.endpoint}</small>
      <span><i className="status-dot" />{telephone.status === 'active' ? 'Ativo' : 'Inativo'}</span>
    </button>

    {open && <div className="rep-modal-backdrop" role="presentation" onMouseDown={() => setOpen(false)}>
      <section className="rep-service-modal" role="dialog" aria-modal="true" aria-label={`Operar ${telephone.label}`} onMouseDown={event => event.stopPropagation()}>
        <header><div><span>Operação</span><strong>{telephone.label}</strong></div><button type="button" onClick={() => setOpen(false)} aria-label="Fechar"><X size={18} /></button></header>
        <TelephoneFull telephone={telephone} />
      </section>
    </div>}
  </>
}
