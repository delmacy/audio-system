import { Radio } from 'lucide-react'
import type { ServiceConfig } from '@/features/simulator/model'

export function RadioPill({ radio }: { radio: ServiceConfig }) {
  return <span className="service-pill radio" title={radio.endpoint}><Radio size={14} />{radio.label}</span>
}
