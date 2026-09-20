import { ChevronRight } from 'lucide-react'
import type { CwpConfig, SimulatorMode } from '@/features/simulator/model'

export function CwpListItem({ cwp, mode, onClick }: {
  cwp: CwpConfig
  mode: SimulatorMode
  onClick?: () => void
}) {
  const config = cwp[mode]

  return <button type="button" className="rep-list-item" onClick={onClick}>
    <strong>{cwp.label}</strong>
    <span>{config.consoleIp}</span>
    <span>{config.radios}R / {config.telephones}T</span>
    <small><i className="status-dot" />Online</small>
    <ChevronRight size={16} />
  </button>
}
