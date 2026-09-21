import { Phone, Radio } from 'lucide-react'
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

export function CwpOperation({
  cwp,
  mode,
  registeredRadios,
  registeredTelephones,
  activeRadioIds,
  onActiveRadioIdsChange,
}: {
  cwp: CwpConfig
  mode: SimulatorMode
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
  const [localActiveRadioIds, setLocalActiveRadioIds] = useState<string[]>(
    ownRadios.filter(service => service.status === 'active').map(service => service.id),
  )
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

  return <div className="cwp-operation">
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

    {dialerSource && <div className="rep-modal-backdrop" role="presentation" onMouseDown={() => setDialerSource(null)}>
      <div className="telephone-dialer-modal" role="dialog" aria-modal="true" aria-label={'Discador ' + dialerSource.label} onMouseDown={event => event.stopPropagation()}>
        <TelephoneDialer source={dialerSource} telephones={telephones} onClose={() => setDialerSource(null)} />
      </div>
    </div>}
  </div>
}
