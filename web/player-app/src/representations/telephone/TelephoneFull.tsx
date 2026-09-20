import { Phone } from 'lucide-react'
import type { ServiceConfig } from '@/features/simulator/model'

export function TelephoneFull({ telephone }: { telephone: ServiceConfig }) {
  return <article className="rep-service-full tel">
    <header><Phone size={24} /><div><strong>{telephone.label}</strong><small><i className="status-dot" />{telephone.status === 'active' ? 'Ativo' : 'Inativo'}</small></div></header>
    <dl>
      <div><dt>Tipo</dt><dd>Telefone</dd></div>
      <div><dt>Endpoint</dt><dd>{telephone.endpoint}</dd></div>
      <div><dt>Status</dt><dd>{telephone.status}</dd></div>
    </dl>
  </article>
}
