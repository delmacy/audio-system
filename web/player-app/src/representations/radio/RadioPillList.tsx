import { RadioPill } from './RadioPill'
import type { ServiceConfig } from '@/features/simulator/model'

export function RadioPillList({ services }: { services: ServiceConfig[] }) {
  return <>{services.filter(service => service.kind === 'RADIO').map(service =>
    <RadioPill key={service.id} radio={service} />
  )}</>
}
