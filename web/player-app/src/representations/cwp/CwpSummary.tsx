import { ChevronRight, Monitor } from 'lucide-react'
import type { CwpConfig, SimulatorMode } from '@/features/simulator/model'

export function CwpSummary({ cwp, mode, onClick }: {
  cwp: CwpConfig
  mode: SimulatorMode
  onClick?: () => void
}) {
  const config = cwp[mode]

  return <button type="button" className="rep-cwp-summary" onClick={onClick}>
    <span className="rep-icon"><Monitor size={18} /></span>
    <strong>{cwp.label}</strong>
    <span>Lado {cwp.side}</span>
    <span>{config.radios} rádios</span>
    <span>{config.telephones} TEL</span>
    <small><i className="status-dot" />Online</small>
    <ChevronRight size={17} />
  </button>
}
