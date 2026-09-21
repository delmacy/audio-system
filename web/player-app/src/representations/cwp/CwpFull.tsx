import { ChevronRight, Monitor, Phone, Radio, Wrench, FileText } from 'lucide-react'
import { useEffect, useState } from 'react'
import { TelephoneDialer } from '@/representations/telephone/TelephoneDialer'
import type { CwpConfig, ServiceConfig, SimulatorMode } from '@/features/simulator/model'

function uniqueServices(services: ServiceConfig[]) {
  const map = new Map<string, ServiceConfig>()
  services.forEach(service => map.set(service.id, service))
  return [...map.values()]
}

export function CwpFull({
  cwp,
  mode,
  expanded,
  onToggle,
  collapsible = true,
  showConfigActions = true,
  registeredRadios,
  registeredTelephones,
  activeRadioIds,
  onActiveRadioIdsChange,
}: {
  cwp: CwpConfig
  mode: SimulatorMode
  expanded: boolean
  onToggle?: () => void
  collapsible?: boolean
  showConfigActions?: boolean
  registeredRadios?: ServiceConfig[]
  registeredTelephones?: ServiceConfig[]
  activeRadioIds?: string[]
  onActiveRadioIdsChange?: (ids: string[]) => void
}) {
  const config = cwp[mode]
  const ownRadios = config.services.filter(service => service.kind === 'RADIO')
  const ownTelephones = config.services.filter(service => service.kind === 'TEL')
  const allRadios = uniqueServices((registeredRadios ?? ownRadios).filter(service => service.kind === 'RADIO'))
  const allTelephones = uniqueServices((registeredTelephones ?? ownTelephones).filter(service => service.kind === 'TEL'))
  const defaultActive = ownRadios.filter(service => service.status === 'active').map(service => service.id)
  const [localActiveRadioIds, setLocalActiveRadioIds] = useState(defaultActive)
  const [dialerOpen, setDialerOpen] = useState(false)

  useEffect(() => {
    if (activeRadioIds === undefined) {
      setLocalActiveRadioIds(
        cwp[mode].services
          .filter(service => service.kind === 'RADIO' && service.status === 'active')
          .map(service => service.id),
      )
    }
  }, [activeRadioIds, cwp, mode])

  const currentActiveRadioIds = activeRadioIds ?? localActiveRadioIds
  const changeActive = (radioId: string, next: boolean) => {
    const updated = next
      ? Array.from(new Set([...currentActiveRadioIds, radioId]))
      : currentActiveRadioIds.filter(id => id !== radioId)
    if (!activeRadioIds) setLocalActiveRadioIds(updated)
    onActiveRadioIdsChange?.(updated)
  }

  const header = <>
    <span className="cwp-icon"><Monitor size={24} /></span>
    <span className="cwp-head">
      <strong>{cwp.label}</strong>
      <small><i className="status-dot" />Online · {config.consoleIp}</small>
    </span>
    {collapsible && <ChevronRight size={20} className={expanded ? 'open' : ''} />}
  </>

  return <article className={'cwp-card' + (expanded ? ' expanded' : '')}>
    {collapsible
      ? <button type="button" className="cwp-main" onClick={onToggle} aria-expanded={expanded}>{header}</button>
      : <div className="cwp-main cwp-main-static">{header}</div>}

    <div className="cwp-meta">
      <span>IP: {config.consoleIp}</span>
      <span>Rádios ativos: {currentActiveRadioIds.length}</span>
      <span>Ramais disponíveis: {allTelephones.length}</span>
    </div>

    <div className="cwp-operation-grid">
      <section className="cwp-radio-activation">
        <header><Radio size={15}/><div><strong>Rádios registrados</strong><small>qualquer rádio cadastrado pode ser ativado neste CWP</small></div></header>
        <div>
          {allRadios.map(radio => {
            const active = currentActiveRadioIds.includes(radio.id)
            return <button type="button" key={radio.id} className={active ? 'active' : ''} onClick={() => changeActive(radio.id, !active)}>
              <span><i />{radio.label}</span>
              <small>{active ? 'ativo' : 'disponível'}</small>
            </button>
          })}
        </div>
        <footer>{mode === 'simulation' ? 'Estado preparado para sincronização por GET_PARAMETERS' : 'Estado operacional do CWP'}</footer>
      </section>

      <section className="cwp-telephone-access">
        <header><Phone size={15}/><div><strong>Telefonia</strong><small>ramais já disponíveis para receber chamadas</small></div></header>
        <button type="button" className="cwp-open-dialer" onClick={() => setDialerOpen(true)}>
          <Phone size={17}/>
          <span><strong>Abrir discador</strong><small>{allTelephones.length} ramais cadastrados</small></span>
        </button>
        <div className="cwp-telephone-directory">
          {allTelephones.map(tel => <span key={tel.id}><i />{tel.label}</span>)}
        </div>
        <footer>Telefonia não depende de GET_PARAMETERS para disponibilidade.</footer>
      </section>
    </div>

    {expanded && <div className="cwp-config-panel">
      <div className="config-grid">
        <label>Console IP<input value={config.consoleIp} readOnly /></label>
        <label>Rádios ativos<input value={currentActiveRadioIds.length} readOnly /></label>
        <label>Ramais disponíveis<input value={allTelephones.length} readOnly /></label>
        <label>Perfil<input value={mode === 'capture' ? 'Captura Real' : 'Simulação de Teste'} readOnly /></label>
      </div>
      <label className="config-note">Observações<textarea value={config.notes} readOnly /></label>
      {showConfigActions && <div className="config-actions">
        <button type="button"><Wrench size={16} />Editar configuração</button>
        <button type="button"><FileText size={16} />Ver serviços</button>
      </div>}
    </div>}

    {dialerOpen && <div className="rep-modal-backdrop" role="presentation" onMouseDown={() => setDialerOpen(false)}>
      <div className="telephone-dialer-modal" role="dialog" aria-modal="true" aria-label={'Discador ' + cwp.label} onMouseDown={event => event.stopPropagation()}>
        <TelephoneDialer sourceLabel={cwp.label} telephones={allTelephones} onClose={() => setDialerOpen(false)} />
      </div>
    </div>}
  </article>
}
