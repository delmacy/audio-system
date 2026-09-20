import { Phone } from 'lucide-react'
import type { ServiceConfig } from '@/features/simulator/model'

export function TelephoneSummary({ telephone, onClick }: { telephone: ServiceConfig; onClick?: () => void }) {
  return <button type="button" className="rep-service-summary tel" onClick={onClick}>
    <Phone size={17} /><strong>{telephone.label}</strong><span>{telephone.endpoint}</span><small><i className="status-dot" />Ativo</small>
  </button>
}
