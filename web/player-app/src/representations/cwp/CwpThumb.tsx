import { Monitor } from 'lucide-react'
import type { CwpConfig, SimulatorMode } from '@/features/simulator/model'

export function CwpThumb({ cwp, mode, onClick }: {
  cwp: CwpConfig
  mode: SimulatorMode
  onClick?: () => void
}) {
  const config = cwp[mode]

  return <button type="button" className="rep-cwp-thumb" onClick={onClick}>
    <span className="rep-thumb-icon"><Monitor size={22} /></span>
    <strong>{cwp.label}</strong>
    <small>Lado {cwp.side} · {config.radios + config.telephones} serviços</small>
    <span><i className="status-dot" />Online</span>
  </button>
}
