import { ChevronRight, FileText, Monitor, Phone, Radio, Wrench } from 'lucide-react'
import { useEffect, useState } from 'react'
import { TelephoneDialer } from '@/representations/telephone/TelephoneDialer'
import type { CwpConfig, ServiceConfig, SimulatorMode } from '@/features/simulator/model'

function uniqueByLabel(services: ServiceConfig[]) {
  const map = new Map<string, ServiceConfig>()
  services.forEach(service => {
    if (!map.has(service.label)) map.set(service.label, service)
  })
  return Array.from(map.values())
}

export function CwpFull({
  cwp,
  mode,
  expanded,
  onToggle,
  collapsible = true,
  showConfigActions = true,
  showDetails = true,
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
  showDetails?: boolean
  registeredRadios?: ServiceConfig[]
  registeredTelephones?: ServiceConfig[]
  activeRadioIds?: string[]
  onActiveRadioIdsChange?: (ids: string[]) => void
}) {
  const config = cwp[mode]
  const ownRadios = config.services.filter(service => service.kind === 'RADIO')
  const ownTelephones = config.services.filter(service => service.kind === 'TEL')
  const radios = uniqueByLabel((registeredRadios ?? ownRadios).filter(service => service.kind === 'RADIO'))
  const telephones = uniqueByLabel((registeredTelephones ?? ownTelephones).filter(service => service.kind === 'TEL'))
  const initialActive = ownRadios.filter(service => service.status === 'active').map(service => service.id)
  const [localActiveRadioIds, setLocalActiveRadioIds] = useState<string[]>(initialActive)
  const [dialerSource, setDialerSource] = useState<ServiceConfig | null>(null)

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

  const setRadioActive = (radioId: string, active: boolean) => {
    const next = active
      ? Array.from(new Set([...currentActiveRadioIds, radioId]))
      : currentActiveRadioIds.filter(id => id !== radioId)
    if (activeRadioIds === undefined) setLocalActiveRadioIds(next)
    onActiveRadioIdsChange?.(next)
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
      <span>Ramais disponíveis: {telephones.length}</span>
    </div>

    <div className="cwp-operation-grid">
      <section className="cwp-operation-section">
        <header>
          <Radio size={15} />
          <div><strong>Rádios registrados</strong><small>qualquer rádio cadastrado pode ser ativado</small></div>
        </header>
        <div className="cwp-radio-list">
          {radios.map(radio => {
            const active = currentActiveRadioIds.includes(radio.id)
            return <button type="button" key={radio.id} className={active ? 'active' : ''} onClick={() => setRadioActive(radio.id, !active)}>
              <span><i />{radio.label}</span>
              <small>{active ? 'ativo' : 'disponível'}</small>
            </button>
          })}
        </div>
        <footer>{mode === 'simulation' ? 'Ativação pronta para persistência via GET_PARAMETERS.' : 'Estado operacional do CWP.'}</footer>
      </section>

      <section className="cwp-operation-section">
        <header>
          <Phone size={15} />
          <div><strong>Telefonia</strong><small>ramais ficam disponíveis sem GET_PARAMETERS</small></div>
        </header>
        <div className="cwp-phone-list">
          {telephones.map(telephone =>
            <button type="button" key={telephone.id} onClick={() => setDialerSource(telephone)}>
              <span><i />{telephone.label}</span>
              <small>abrir discador</small>
            </button>
          )}
        </div>
        <footer>Selecione um telefone para chamar outro ramal cadastrado.</footer>
      </section>
    </div>

    {expanded && showDetails && <div className="cwp-config-panel">
      <div className="config-grid">
        <label>Console IP<input value={config.consoleIp} readOnly /></label>
        <label>Rádios ativos<input value={currentActiveRadioIds.length} readOnly /></label>
        <label>Ramais disponíveis<input value={telephones.length} readOnly /></label>
        <label>Perfil<input value={mode === 'capture' ? 'Captura Real' : 'Simulação de Teste'} readOnly /></label>
      </div>
      <label className="config-note">Observações<textarea value={config.notes} readOnly /></label>
      {showConfigActions && <div className="config-actions">
        <button type="button"><Wrench size={16} />Editar configuração</button>
        <button type="button"><FileText size={16} />Ver serviços</button>
      </div>}
    </div>}

    {dialerSource && <div className="rep-modal-backdrop" role="presentation" onMouseDown={() => setDialerSource(null)}>
      <div className="telephone-dialer-modal" role="dialog" aria-modal="true" aria-label={'Discador ' + dialerSource.label} onMouseDown={event => event.stopPropagation()}>
        <TelephoneDialer source={dialerSource} telephones={telephones} onClose={() => setDialerSource(null)} />
      </div>
    </div>}
  </article>
}
