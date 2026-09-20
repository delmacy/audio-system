import { Radio } from 'lucide-react'
import type { ServiceConfig } from '@/features/simulator/model'

export function RadioSummary({ radio, onClick }: { radio: ServiceConfig; onClick?: () => void }) {
  return <button type="button" className="rep-service-summary radio" onClick={onClick}>
    <Radio size={17} /><strong>{radio.label}</strong><span>{radio.endpoint}</span><small><i className="status-dot" />Ativo</small>
  </button>
}
