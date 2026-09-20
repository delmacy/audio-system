import { ServicePill } from '../elements/ServicePill'
import type { ServiceConfig } from '../model'

export function TelephoneList({ services }: { services: ServiceConfig[] }) {
  return <>{services.filter(service => service.kind === 'TEL').map(service =>
    <ServicePill key={service.id} service={service} />
  )}</>
}
