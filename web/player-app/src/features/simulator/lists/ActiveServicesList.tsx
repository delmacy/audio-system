import type { ServiceConfig } from '../model'

export type ActiveServiceRow = ServiceConfig & { cwp: string; side: 'A' | 'B' }

export function ActiveServicesList({ services }: { services: ActiveServiceRow[] }) {
  return <div className="services-table">
    {services.map(service => <div key={service.id} className="service-row">
      <span className={`svc-kind ${service.kind.toLowerCase()}`}>{service.kind}</span>
      <strong>{service.label}</strong>
      <span>{service.cwp}</span>
      <span>Lado {service.side}</span>
      <small><i className="status-dot" />Ativo</small>
    </div>)}
  </div>
}
