import { Phone } from 'lucide-react'
import type { ServiceConfig } from '@/features/simulator/model'

export function TelephonePill({ telephone }: { telephone: ServiceConfig }) {
  return <span className="service-pill tel" title={telephone.endpoint}><Phone size={14} />{telephone.label}</span>
}
