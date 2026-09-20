import { ServicePill } from '../elements/ServicePill'
import type { ServiceConfig } from '../model'

export function RadioList({ services }: { services: ServiceConfig[] }) {
  return <>{services.filter(service => service.kind === 'RADIO').map(service =>
    <ServicePill key={service.id} service={service} />
  )}</>
}
