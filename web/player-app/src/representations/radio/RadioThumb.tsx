import { Radio, X } from 'lucide-react'
import { useState } from 'react'
import { RadioFull } from './RadioFull'
import type { ServiceConfig } from '@/features/simulator/model'

export function RadioThumb({ radio }: { radio: ServiceConfig }) {
  const [open, setOpen] = useState(false)

  return <>
    <button type="button" className="rep-service-thumb radio" onClick={() => setOpen(true)}>
      <span className="rep-thumb-icon"><Radio size={22} /></span>
      <strong>{radio.label}</strong>
      <small>{radio.endpoint}</small>
      <span><i className="status-dot" />{radio.status === 'active' ? 'Ativo' : 'Inativo'}</span>
    </button>

    {open && <div className="rep-modal-backdrop" role="presentation" onMouseDown={() => setOpen(false)}>
      <section className="rep-service-modal" role="dialog" aria-modal="true" aria-label={`Operar ${radio.label}`} onMouseDown={event => event.stopPropagation()}>
        <header><div><span>Operação</span><strong>{radio.label}</strong></div><button type="button" onClick={() => setOpen(false)} aria-label="Fechar"><X size={18} /></button></header>
        <RadioFull radio={radio} />
      </section>
    </div>}
  </>
}
