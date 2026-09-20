import { Phone, Radio } from 'lucide-react'
import type { ServiceConfig } from '../model'
export function ServicePill({ service }: { service: ServiceConfig }) {
  const Icon = service.kind === 'RADIO' ? Radio : Phone
  return <span className={`service-pill ${service.kind.toLowerCase()}`} title={service.endpoint}>
    <Icon size={14} />{service.label}
  </span>
}

