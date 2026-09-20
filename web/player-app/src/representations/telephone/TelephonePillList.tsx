import { TelephonePill } from './TelephonePill'
import type { ServiceConfig } from '@/features/simulator/model'

export function TelephonePillList({ services }: { services: ServiceConfig[] }) {
  return <>{services.filter(service => service.kind === 'TEL').map(service =>
    <TelephonePill key={service.id} telephone={service} />
  )}</>
}
