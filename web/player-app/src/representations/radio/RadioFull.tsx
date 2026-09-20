import { Radio } from 'lucide-react'
import type { ServiceConfig } from '@/features/simulator/model'

export function RadioFull({ radio }: { radio: ServiceConfig }) {
  return <article className="rep-service-full radio">
    <header><Radio size={24} /><div><strong>{radio.label}</strong><small><i className="status-dot" />{radio.status === 'active' ? 'Ativo' : 'Inativo'}</small></div></header>
    <dl>
      <div><dt>Tipo</dt><dd>Rádio</dd></div>
      <div><dt>Endpoint</dt><dd>{radio.endpoint}</dd></div>
      <div><dt>Status</dt><dd>{radio.status}</dd></div>
    </dl>
  </article>
}
