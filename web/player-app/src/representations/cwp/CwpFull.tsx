import { ChevronRight, FileText, Monitor, Wrench } from 'lucide-react'
import { RadioPillList } from '@/representations/radio/RadioPillList'
import { TelephonePillList } from '@/representations/telephone/TelephonePillList'
import type { CwpConfig, SimulatorMode } from '@/features/simulator/model'

export function CwpFull({ cwp, mode, expanded, onToggle, collapsible = true, showConfigActions = true }: {
  cwp: CwpConfig
  mode: SimulatorMode
  expanded: boolean
  onToggle?: () => void
  collapsible?: boolean
  showConfigActions?: boolean
}) {
  const config = cwp[mode]
  const header = <>
    <span className="cwp-icon"><Monitor size={24} /></span>
    <span className="cwp-head"><strong>{cwp.label}</strong><small><i className="status-dot" />Online</small></span>
    {collapsible && <ChevronRight size={20} className={expanded ? 'open' : ''} />}
  </>

  return <article className={'cwp-card' + (expanded ? ' expanded' : '')}>
    {collapsible
      ? <button type="button" className="cwp-main" onClick={onToggle} aria-expanded={expanded}>{header}</button>
      : <div className="cwp-main cwp-main-static">{header}</div>}

    <div className="cwp-meta">
      <span>IP: {config.consoleIp}</span>
      <span>Rádios: {config.radios}</span>
      <span>Telefones: {config.telephones}</span>
    </div>

    <div className="cwp-services">
      <RadioPillList services={config.services} />
      <TelephonePillList services={config.services} />
    </div>

    {expanded && <div className="cwp-config-panel">
      <div className="config-grid">
        <label>Console IP<input value={config.consoleIp} readOnly /></label>
        <label>Rádios ativos<input value={config.radios} readOnly /></label>
        <label>Telefones ativos<input value={config.telephones} readOnly /></label>
        <label>Perfil<input value={mode === 'capture' ? 'Captura Real' : 'Simulação de Teste'} readOnly /></label>
      </div>
      <label className="config-note">Observações<textarea value={config.notes} readOnly /></label>
      {showConfigActions && <div className="config-actions">
        <button type="button"><Wrench size={16} />Editar configuração</button>
        <button type="button"><FileText size={16} />Ver serviços</button>
      </div>}
    </div>}
  </article>
}
