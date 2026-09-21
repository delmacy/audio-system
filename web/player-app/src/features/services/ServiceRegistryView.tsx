import { Plus, Radio, Phone, Trash2, Monitor } from 'lucide-react'
import { useMemo, useState } from 'react'
import type { CwpConfig, ServiceConfig, SimulatorMode } from '@/features/simulator/model'
import { SIM_CWPS } from '@/features/simulator/model'

type RegistryService = ServiceConfig & { registryId: string }

function uniqueServices(cwps: CwpConfig[], mode: SimulatorMode): RegistryService[] {
  const map = new Map<string, RegistryService>()
  cwps.flatMap(cwp => cwp[mode].services).forEach(service => {
    const key = service.kind + ':' + service.label
    if (!map.has(key)) map.set(key, { ...service, registryId: key })
  })
  return Array.from(map.values())
}

export function ServiceRegistryView({ mode = 'simulation' }: { mode?: SimulatorMode }) {
  const [cwps, setCwps] = useState<CwpConfig[]>(SIM_CWPS)
  const [services, setServices] = useState<RegistryService[]>(() => uniqueServices(SIM_CWPS, mode))
  const [cwpFormOpen, setCwpFormOpen] = useState(false)
  const [serviceFormOpen, setServiceFormOpen] = useState(false)
  const [cwpLabel, setCwpLabel] = useState('')
  const [cwpIp, setCwpIp] = useState('')
  const [cwpSide, setCwpSide] = useState<'A' | 'B'>('A')
  const [serviceKind, setServiceKind] = useState<'RADIO' | 'TEL'>('RADIO')
  const [serviceLabel, setServiceLabel] = useState('')
  const [serviceEndpoint, setServiceEndpoint] = useState('')

  const stats = useMemo(() => ({
    cwps: cwps.length,
    radios: services.filter(service => service.kind === 'RADIO').length,
    telephones: services.filter(service => service.kind === 'TEL').length,
  }), [cwps, services])

  const addCwp = () => {
    const label = cwpLabel.trim()
    const ip = cwpIp.trim()
    if (!label || !ip) return
    const id = 'cwp-local-' + Date.now()
    const config = { consoleIp: ip, radios: 0, telephones: 0, services: [] as ServiceConfig[], notes: '' }
    setCwps(current => [...current, { id, label, side: cwpSide, capture: { ...config }, simulation: { ...config } }])
    setCwpLabel('')
    setCwpIp('')
    setCwpSide('A')
    setCwpFormOpen(false)
  }

  const addService = () => {
    const label = serviceLabel.trim()
    const endpoint = serviceEndpoint.trim()
    if (!label || !endpoint) return
    const registryId = serviceKind + ':' + label
    setServices(current => current.some(service => service.registryId === registryId)
      ? current
      : [...current, {
          id: 'service-local-' + Date.now(),
          registryId,
          kind: serviceKind,
          label,
          endpoint,
          status: 'active',
        }])
    setServiceLabel('')
    setServiceEndpoint('')
    setServiceKind('RADIO')
    setServiceFormOpen(false)
  }

  return <main className="registry-page">
    <header className="registry-page-header">
      <div>
        <span className="registry-eyebrow">Configuração do sistema</span>
        <h1>Serviços & CWP</h1>
        <p>Inclua ou exclua consoles, rádios e ramais disponíveis para composição do simulador.</p>
      </div>
      <div className="registry-summary">
        <span><strong>{stats.cwps}</strong>CWP</span>
        <span><strong>{stats.radios}</strong>Rádios</span>
        <span><strong>{stats.telephones}</strong>Telefones</span>
      </div>
    </header>

    <section className="registry-section">
      <header>
        <div>
          <span className="registry-section-icon"><Monitor size={17} /></span>
          <div><strong>CWP</strong><small>Consoles cadastrados no sistema</small></div>
        </div>
        <button type="button" className="registry-add-button" onClick={() => setCwpFormOpen(value => !value)}>
          <Plus size={16} />Incluir CWP
        </button>
      </header>

      {cwpFormOpen && <div className="registry-inline-form">
        <label>Nome<input value={cwpLabel} onChange={event => setCwpLabel(event.target.value)} placeholder="CWP-003" /></label>
        <label>IP<input value={cwpIp} onChange={event => setCwpIp(event.target.value)} placeholder="10.20.1.103" /></label>
        <label>Lado<select value={cwpSide} onChange={event => setCwpSide(event.target.value as 'A' | 'B')}><option value="A">A</option><option value="B">B</option></select></label>
        <div>
          <button type="button" onClick={() => setCwpFormOpen(false)}>Cancelar</button>
          <button type="button" className="primary" onClick={addCwp} disabled={!cwpLabel.trim() || !cwpIp.trim()}>Adicionar</button>
        </div>
      </div>}

      <div className="registry-list">
        {cwps.map(cwp => {
          const config = cwp[mode]
          return <article className="registry-row" key={cwp.id}>
            <span className="registry-row-icon"><Monitor size={17} /></span>
            <div className="registry-row-main">
              <strong>{cwp.label}</strong>
              <small>{config.consoleIp}</small>
            </div>
            <span className="registry-row-meta">Lado {cwp.side}</span>
            <span className="registry-row-meta">{config.radios}R / {config.telephones}T</span>
            <span className="registry-row-state"><i />Online</span>
            <button type="button" className="registry-delete" onClick={() => setCwps(current => current.filter(item => item.id !== cwp.id))} aria-label={'Excluir ' + cwp.label}>
              <Trash2 size={15} />
            </button>
          </article>
        })}
      </div>
    </section>

    <section className="registry-section">
      <header>
        <div>
          <span className="registry-section-icon"><Radio size={17} /></span>
          <div><strong>Serviços</strong><small>Rádios e ramais disponíveis no sistema</small></div>
        </div>
        <button type="button" className="registry-add-button" onClick={() => setServiceFormOpen(value => !value)}>
          <Plus size={16} />Incluir serviço
        </button>
      </header>

      {serviceFormOpen && <div className="registry-inline-form service">
        <label>Tipo<select value={serviceKind} onChange={event => setServiceKind(event.target.value as 'RADIO' | 'TEL')}>
          <option value="RADIO">Rádio</option><option value="TEL">Telefone</option>
        </select></label>
        <label>Nome<input value={serviceLabel} onChange={event => setServiceLabel(event.target.value)} placeholder={serviceKind === 'RADIO' ? 'TWR 121.500' : 'TEL-050'} /></label>
        <label>Endpoint<input value={serviceEndpoint} onChange={event => setServiceEndpoint(event.target.value)} placeholder={serviceKind === 'RADIO' ? 'rtsp://...' : 'sip:...'} /></label>
        <div>
          <button type="button" onClick={() => setServiceFormOpen(false)}>Cancelar</button>
          <button type="button" className="primary" onClick={addService} disabled={!serviceLabel.trim() || !serviceEndpoint.trim()}>Adicionar</button>
        </div>
      </div>}

      <div className="registry-list">
        {services.map(service => <article className="registry-row" key={service.registryId}>
          <span className={'registry-row-icon ' + service.kind.toLowerCase()}>
            {service.kind === 'RADIO' ? <Radio size={17} /> : <Phone size={17} />}
          </span>
          <div className="registry-row-main">
            <strong>{service.label}</strong>
            <small>{service.endpoint}</small>
          </div>
          <span className={'registry-kind ' + service.kind.toLowerCase()}>{service.kind === 'RADIO' ? 'RÁDIO' : 'TEL'}</span>
          <span className="registry-row-meta">Disponível</span>
          <span className="registry-row-state"><i />Ativo</span>
          <button type="button" className="registry-delete" onClick={() => setServices(current => current.filter(item => item.registryId !== service.registryId))} aria-label={'Excluir ' + service.label}>
            <Trash2 size={15} />
          </button>
        </article>)}
      </div>
    </section>
  </main>
}
