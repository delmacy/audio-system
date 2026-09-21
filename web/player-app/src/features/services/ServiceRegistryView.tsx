import { AlertTriangle, ArrowRightLeft, Monitor, Pencil, Phone, Plus, Radio, RefreshCw, Trash2, X } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'

type ApiCwp = {
  id: string
  label: string
  ip: string
  side: 'A' | 'B'
  enabled: boolean
  ip_source: 'auto' | 'manual'
}

type ApiGateway = {
  id: string
  label: string
  ip: string
  sip_port: number
  rtsp_base_url: string
  enabled: boolean
}

type ApiService = {
  id: string
  kind: 'RADIO' | 'TEL'
  label: string
  endpoint: string
  sip_uri: string | null
  gateway_id: string | null
  gateway_label: string | null
  gateway_rtsp_base_url: string | null
  legacy_rtsp: boolean
  enabled: boolean
}

type ConfigPayload = {
  schema: string
  network: { allocation: string; next_cwp_ip: string }
  cwps: ApiCwp[]
  gateways: ApiGateway[]
  services: ApiService[]
}

type DeleteTarget = {
  type: 'cwp' | 'service' | 'gateway'
  id: string
  label: string
}

async function responseJson(response: Response) {
  const payload = await response.json().catch(() => null) as { detail?: string } | null
  if (!response.ok) throw new Error(payload?.detail || `HTTP ${response.status}`)
  return payload
}

export function ServiceRegistryView() {
  const [cwps, setCwps] = useState<ApiCwp[]>([])
  const [gateways, setGateways] = useState<ApiGateway[]>([])
  const [services, setServices] = useState<ApiService[]>([])
  const [nextIp, setNextIp] = useState('')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const [cwpFormOpen, setCwpFormOpen] = useState(false)
  const [serviceFormOpen, setServiceFormOpen] = useState(false)
  const [gatewayFormOpen, setGatewayFormOpen] = useState(false)

  const [cwpLabel, setCwpLabel] = useState('')
  const [cwpIp, setCwpIp] = useState('')
  const [cwpSide, setCwpSide] = useState<'A' | 'B'>('A')

  const [serviceKind, setServiceKind] = useState<'RADIO' | 'TEL'>('RADIO')
  const [serviceLabel, setServiceLabel] = useState('')
  const [serviceSipUri, setServiceSipUri] = useState('')
  const [serviceGatewayId, setServiceGatewayId] = useState('')

  const [gatewayLabel, setGatewayLabel] = useState('')
  const [gatewayIp, setGatewayIp] = useState('')
  const [gatewaySipPort, setGatewaySipPort] = useState('5060')
  const [gatewayRtspBaseUrl, setGatewayRtspBaseUrl] = useState('')

  const [editingCwp, setEditingCwp] = useState<ApiCwp | null>(null)
  const [editingService, setEditingService] = useState<ApiService | null>(null)
  const [editingGateway, setEditingGateway] = useState<ApiGateway | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<DeleteTarget | null>(null)

  const [editCwpLabel, setEditCwpLabel] = useState('')
  const [editCwpIp, setEditCwpIp] = useState('')
  const [editCwpSide, setEditCwpSide] = useState<'A' | 'B'>('A')

  const [editServiceKind, setEditServiceKind] = useState<'RADIO' | 'TEL'>('RADIO')
  const [editServiceLabel, setEditServiceLabel] = useState('')
  const [editServiceSipUri, setEditServiceSipUri] = useState('')
  const [editServiceGatewayId, setEditServiceGatewayId] = useState('')

  const [editGatewayLabel, setEditGatewayLabel] = useState('')
  const [editGatewayIp, setEditGatewayIp] = useState('')
  const [editGatewaySipPort, setEditGatewaySipPort] = useState('5060')
  const [editGatewayRtspBaseUrl, setEditGatewayRtspBaseUrl] = useState('')

  const stats = useMemo(() => ({
    cwps: cwps.length,
    radios: services.filter(service => service.kind === 'RADIO').length,
    telephones: services.filter(service => service.kind === 'TEL').length,
    gateways: gateways.length,
  }), [cwps, gateways, services])

  const load = async () => {
    setLoading(true)
    setError('')
    try {
      const payload = await responseJson(await fetch('/api/config', { headers: { Accept: 'application/json' } })) as ConfigPayload
      setCwps(payload.cwps)
      setGateways(payload.gateways ?? [])
      setServices(payload.services)
      setNextIp(payload.network.next_cwp_ip)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao carregar configuração.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    void load()
  }, [])

  const openCwpForm = async () => {
    setCwpFormOpen(value => !value)
    setError('')
    try {
      const payload = await responseJson(await fetch('/api/network/next-ip', { headers: { Accept: 'application/json' } })) as { ip: string }
      setNextIp(payload.ip)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao consultar próximo IP.')
    }
  }

  const addCwp = async () => {
    if (!cwpLabel.trim()) return
    setSaving(true)
    setError('')
    try {
      await responseJson(await fetch('/api/cwps', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({ label: cwpLabel.trim(), side: cwpSide, ip: cwpIp.trim() || null }),
      }))
      setCwpLabel('')
      setCwpIp('')
      setCwpSide('A')
      setCwpFormOpen(false)
      await load()
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao cadastrar CWP.')
    } finally {
      setSaving(false)
    }
  }

  const addService = async () => {
    if (!serviceLabel.trim() || !serviceSipUri.trim()) return
    if (serviceKind === 'RADIO' && !serviceGatewayId) return
    setSaving(true)
    setError('')
    try {
      await responseJson(await fetch('/api/services', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({
          kind: serviceKind,
          label: serviceLabel.trim(),
          sip_uri: serviceSipUri.trim(),
          gateway_id: serviceKind === 'RADIO' ? serviceGatewayId : null,
        }),
      }))
      setServiceLabel('')
      setServiceSipUri('')
      setServiceKind('RADIO')
      setServiceGatewayId('')
      setServiceFormOpen(false)
      await load()
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao cadastrar serviço.')
    } finally {
      setSaving(false)
    }
  }

  const addGateway = async () => {
    if (!gatewayLabel.trim() || !gatewayIp.trim() || !gatewayRtspBaseUrl.trim()) return
    setSaving(true)
    setError('')
    try {
      await responseJson(await fetch('/api/gateways', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({
          label: gatewayLabel.trim(),
          ip: gatewayIp.trim(),
          sip_port: Number(gatewaySipPort),
          rtsp_base_url: gatewayRtspBaseUrl.trim(),
        }),
      }))
      setGatewayLabel('')
      setGatewayIp('')
      setGatewaySipPort('5060')
      setGatewayRtspBaseUrl('')
      setGatewayFormOpen(false)
      await load()
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao cadastrar gateway.')
    } finally {
      setSaving(false)
    }
  }

  const startEditCwp = (item: ApiCwp) => {
    setEditingCwp(item)
    setEditCwpLabel(item.label)
    setEditCwpIp(item.ip)
    setEditCwpSide(item.side)
  }

  const startEditService = (item: ApiService) => {
    setEditingService(item)
    setEditServiceKind(item.kind)
    setEditServiceLabel(item.label)
    setEditServiceSipUri(item.sip_uri ?? '')
    setEditServiceGatewayId(item.gateway_id ?? '')
  }

  const startEditGateway = (item: ApiGateway) => {
    setEditingGateway(item)
    setEditGatewayLabel(item.label)
    setEditGatewayIp(item.ip)
    setEditGatewaySipPort(String(item.sip_port))
    setEditGatewayRtspBaseUrl(item.rtsp_base_url)
  }

  const saveCwpEdit = async () => {
    if (!editingCwp || !editCwpLabel.trim() || !editCwpIp.trim()) return
    setSaving(true)
    try {
      await responseJson(await fetch('/api/cwps/' + encodeURIComponent(editingCwp.id), {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({ label: editCwpLabel.trim(), ip: editCwpIp.trim(), side: editCwpSide }),
      }))
      setEditingCwp(null)
      await load()
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao editar CWP.')
    } finally {
      setSaving(false)
    }
  }

  const saveServiceEdit = async () => {
    if (!editingService || !editServiceLabel.trim() || !editServiceSipUri.trim()) return
    if (editServiceKind === 'RADIO' && !editServiceGatewayId) return
    setSaving(true)
    try {
      await responseJson(await fetch('/api/services/' + encodeURIComponent(editingService.id), {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({
          kind: editServiceKind,
          label: editServiceLabel.trim(),
          sip_uri: editServiceSipUri.trim(),
          gateway_id: editServiceKind === 'RADIO' ? editServiceGatewayId : null,
        }),
      }))
      setEditingService(null)
      await load()
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao editar serviço.')
    } finally {
      setSaving(false)
    }
  }

  const saveGatewayEdit = async () => {
    if (!editingGateway || !editGatewayLabel.trim() || !editGatewayIp.trim() || !editGatewayRtspBaseUrl.trim()) return
    setSaving(true)
    try {
      await responseJson(await fetch('/api/gateways/' + encodeURIComponent(editingGateway.id), {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({
          label: editGatewayLabel.trim(),
          ip: editGatewayIp.trim(),
          sip_port: Number(editGatewaySipPort),
          rtsp_base_url: editGatewayRtspBaseUrl.trim(),
        }),
      }))
      setEditingGateway(null)
      await load()
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao editar gateway.')
    } finally {
      setSaving(false)
    }
  }

  const deleteConfirmed = async () => {
    if (!deleteTarget) return
    const target = deleteTarget
    setDeleteTarget(null)
    setSaving(true)
    setError('')
    try {
      const path = target.type === 'cwp'
        ? '/api/cwps/'
        : target.type === 'service'
          ? '/api/services/'
          : '/api/gateways/'
      await responseJson(await fetch(path + encodeURIComponent(target.id), { method: 'DELETE' }))
      await load()
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao excluir cadastro.')
    } finally {
      setSaving(false)
    }
  }

  const gatewayOptions = (selected: string) => <select value={selected} onChange={() => undefined} aria-hidden="true" />

  return <main className="registry-page">
    <header className="registry-page-header">
      <div>
        <span className="registry-eyebrow">Configuração persistente · SQLite</span>
        <h1>Serviços & CWP</h1>
        <p>Rádios e telefones são serviços SIP. Rádios usam um gateway para encaminhar mídia ao destino RTSP do gravador.</p>
      </div>
      <div className="registry-summary">
        <span><strong>{stats.cwps}</strong>CWP</span>
        <span><strong>{stats.radios}</strong>Rádios</span>
        <span><strong>{stats.telephones}</strong>Telefones</span>
        <span><strong>{stats.gateways}</strong>Gateways</span>
      </div>
    </header>

    {(loading || error) && <div className={'registry-api-state' + (error ? ' error' : '')}>
      <span>{loading ? 'Carregando configuração…' : error}</span>
      {!loading && <button type="button" onClick={() => void load()}><RefreshCw size={14} />Tentar novamente</button>}
    </div>}

    <section className="registry-section">
      <header>
        <div>
          <span className="registry-section-icon"><Monitor size={17} /></span>
          <div><strong>CWP</strong><small>Consoles persistidos no banco</small></div>
        </div>
        <button type="button" className="registry-add-button" onClick={() => void openCwpForm()}><Plus size={16} />Incluir CWP</button>
      </header>

      {cwpFormOpen && <div className="registry-inline-form">
        <label>Nome<input value={cwpLabel} onChange={event => setCwpLabel(event.target.value)} placeholder="CWP-003" /></label>
        <label>IP<input value={cwpIp} onChange={event => setCwpIp(event.target.value)} placeholder={nextIp ? 'Auto: ' + nextIp : 'Automático'} /><small>Vazio = próximo IP livre.</small></label>
        <label>Lado<select value={cwpSide} onChange={event => setCwpSide(event.target.value as 'A' | 'B')}><option value="A">A</option><option value="B">B</option></select></label>
        <div><button type="button" onClick={() => setCwpFormOpen(false)}>Cancelar</button><button type="button" className="primary" onClick={() => void addCwp()} disabled={saving || !cwpLabel.trim()}>Adicionar</button></div>
      </div>}

      <div className="registry-list">
        {cwps.map(cwp => <article className="registry-row" key={cwp.id}>
          <span className="registry-row-icon"><Monitor size={17} /></span>
          <div className="registry-row-main"><strong>{cwp.label}</strong><small>{cwp.ip}</small></div>
          <span className="registry-row-meta">Lado {cwp.side}</span>
          <span className={'registry-ip-source ' + cwp.ip_source}>{cwp.ip_source === 'auto' ? 'AUTO IP' : 'MANUAL'}</span>
          <span className="registry-row-state"><i />{cwp.enabled ? 'Ativo' : 'Inativo'}</span>
          <div className="registry-row-actions">
            <button type="button" className="registry-edit" onClick={() => startEditCwp(cwp)}><Pencil size={14} /></button>
            <button type="button" className="registry-delete" onClick={() => setDeleteTarget({ type: 'cwp', id: cwp.id, label: cwp.label })}><Trash2 size={15} /></button>
          </div>
        </article>)}
      </div>
    </section>

    <section className="registry-section">
      <header>
        <div>
          <span className="registry-section-icon"><ArrowRightLeft size={17} /></span>
          <div><strong>Gateway SIP → RTSP</strong><small>Fronteira de mídia entre os serviços SIP e o gravador</small></div>
        </div>
        <button type="button" className="registry-add-button" onClick={() => setGatewayFormOpen(value => !value)}><Plus size={16} />Incluir gateway</button>
      </header>

      {gatewayFormOpen && <div className="registry-inline-form gateway">
        <label>Nome<input value={gatewayLabel} onChange={event => setGatewayLabel(event.target.value)} placeholder="Gateway principal" /></label>
        <label>IP SIP<input value={gatewayIp} onChange={event => setGatewayIp(event.target.value)} placeholder="10.10.0.20" /></label>
        <label>Porta SIP<input type="number" value={gatewaySipPort} onChange={event => setGatewaySipPort(event.target.value)} /></label>
        <label>Destino RTSP<input value={gatewayRtspBaseUrl} onChange={event => setGatewayRtspBaseUrl(event.target.value)} placeholder="rtsp://10.10.0.10:8554" /></label>
        <div><button type="button" onClick={() => setGatewayFormOpen(false)}>Cancelar</button><button type="button" className="primary" onClick={() => void addGateway()} disabled={saving || !gatewayLabel.trim() || !gatewayIp.trim() || !gatewayRtspBaseUrl.trim()}>Adicionar</button></div>
      </div>}

      <div className="registry-list">
        {gateways.map(gateway => <article className="registry-row" key={gateway.id}>
          <span className="registry-row-icon gateway"><ArrowRightLeft size={17} /></span>
          <div className="registry-row-main"><strong>{gateway.label}</strong><small>{gateway.ip}:{gateway.sip_port}</small></div>
          <span className="registry-kind gateway">SIP→RTSP</span>
          <span className="registry-row-meta registry-row-rtsp">{gateway.rtsp_base_url}</span>
          <span className="registry-row-state"><i />{gateway.enabled ? 'Ativo' : 'Inativo'}</span>
          <div className="registry-row-actions">
            <button type="button" className="registry-edit" onClick={() => startEditGateway(gateway)}><Pencil size={14} /></button>
            <button type="button" className="registry-delete" onClick={() => setDeleteTarget({ type: 'gateway', id: gateway.id, label: gateway.label })}><Trash2 size={15} /></button>
          </div>
        </article>)}
      </div>
    </section>

    <section className="registry-section">
      <header>
        <div>
          <span className="registry-section-icon"><Radio size={17} /></span>
          <div><strong>Serviços SIP</strong><small>Rádios e ramais cadastrados no sistema</small></div>
        </div>
        <button type="button" className="registry-add-button" onClick={() => setServiceFormOpen(value => !value)}><Plus size={16} />Incluir serviço</button>
      </header>

      {serviceFormOpen && <div className="registry-inline-form service sip-service">
        <label>Tipo<select value={serviceKind} onChange={event => setServiceKind(event.target.value as 'RADIO' | 'TEL')}><option value="RADIO">Rádio</option><option value="TEL">Telefone</option></select></label>
        <label>Nome<input value={serviceLabel} onChange={event => setServiceLabel(event.target.value)} placeholder={serviceKind === 'RADIO' ? 'TWR 121.500' : 'TEL-050'} /></label>
        <label>URI SIP<input value={serviceSipUri} onChange={event => setServiceSipUri(event.target.value)} placeholder="sip:servico@10.10.0.20:5060" /></label>
        {serviceKind === 'RADIO' && <label>Gateway<select value={serviceGatewayId} onChange={event => setServiceGatewayId(event.target.value)}><option value="">Selecione</option>{gateways.map(gateway => <option value={gateway.id} key={gateway.id}>{gateway.label}</option>)}</select></label>}
        <div><button type="button" onClick={() => setServiceFormOpen(false)}>Cancelar</button><button type="button" className="primary" onClick={() => void addService()} disabled={saving || !serviceLabel.trim() || !serviceSipUri.trim() || (serviceKind === 'RADIO' && !serviceGatewayId)}>Adicionar</button></div>
      </div>}

      <div className="registry-list">
        {services.map(service => <article className={'registry-row' + (service.legacy_rtsp ? ' legacy' : '')} key={service.id}>
          <span className={'registry-row-icon ' + service.kind.toLowerCase()}>{service.kind === 'RADIO' ? <Radio size={17} /> : <Phone size={17} />}</span>
          <div className="registry-row-main">
            <strong>{service.label}</strong>
            <small>{service.sip_uri ?? service.endpoint}</small>
          </div>
          <span className={'registry-kind ' + service.kind.toLowerCase()}>{service.kind === 'RADIO' ? 'RÁDIO SIP' : 'TEL SIP'}</span>
          <span className="registry-row-meta">{service.kind === 'RADIO' ? (service.gateway_label ?? (service.legacy_rtsp ? 'Legado RTSP' : 'Sem gateway')) : 'SIP direto'}</span>
          <span className="registry-row-state"><i />{service.legacy_rtsp ? 'Migrar' : service.enabled ? 'Ativo' : 'Inativo'}</span>
          <div className="registry-row-actions">
            <button type="button" className="registry-edit" onClick={() => startEditService(service)}><Pencil size={14} /></button>
            <button type="button" className="registry-delete" onClick={() => setDeleteTarget({ type: 'service', id: service.id, label: service.label })}><Trash2 size={15} /></button>
          </div>
        </article>)}
      </div>
    </section>

    {editingCwp && <div className="registry-modal-backdrop" onMouseDown={() => setEditingCwp(null)}>
      <section className="registry-modal" onMouseDown={event => event.stopPropagation()}>
        <header><div><span>Editar CWP</span><strong>{editingCwp.label}</strong></div><button type="button" onClick={() => setEditingCwp(null)}><X size={17} /></button></header>
        <div className="registry-modal-form">
          <label>Nome<input value={editCwpLabel} onChange={event => setEditCwpLabel(event.target.value)} /></label>
          <label>IP<input value={editCwpIp} onChange={event => setEditCwpIp(event.target.value)} /></label>
          <label>Lado<select value={editCwpSide} onChange={event => setEditCwpSide(event.target.value as 'A' | 'B')}><option value="A">A</option><option value="B">B</option></select></label>
        </div>
        <footer><button type="button" onClick={() => setEditingCwp(null)}>Cancelar</button><button type="button" className="primary" onClick={() => void saveCwpEdit()}>Salvar alterações</button></footer>
      </section>
    </div>}

    {editingGateway && <div className="registry-modal-backdrop" onMouseDown={() => setEditingGateway(null)}>
      <section className="registry-modal" onMouseDown={event => event.stopPropagation()}>
        <header><div><span>Editar gateway</span><strong>{editingGateway.label}</strong></div><button type="button" onClick={() => setEditingGateway(null)}><X size={17} /></button></header>
        <div className="registry-modal-form">
          <label>Nome<input value={editGatewayLabel} onChange={event => setEditGatewayLabel(event.target.value)} /></label>
          <label>IP SIP<input value={editGatewayIp} onChange={event => setEditGatewayIp(event.target.value)} /></label>
          <label>Porta SIP<input type="number" value={editGatewaySipPort} onChange={event => setEditGatewaySipPort(event.target.value)} /></label>
          <label>Destino RTSP<input value={editGatewayRtspBaseUrl} onChange={event => setEditGatewayRtspBaseUrl(event.target.value)} /></label>
        </div>
        <footer><button type="button" onClick={() => setEditingGateway(null)}>Cancelar</button><button type="button" className="primary" onClick={() => void saveGatewayEdit()}>Salvar alterações</button></footer>
      </section>
    </div>}

    {editingService && <div className="registry-modal-backdrop" onMouseDown={() => setEditingService(null)}>
      <section className="registry-modal" onMouseDown={event => event.stopPropagation()}>
        <header><div><span>Editar serviço SIP</span><strong>{editingService.label}</strong></div><button type="button" onClick={() => setEditingService(null)}><X size={17} /></button></header>
        <div className="registry-modal-form">
          <label>Tipo<select value={editServiceKind} onChange={event => setEditServiceKind(event.target.value as 'RADIO' | 'TEL')}><option value="RADIO">Rádio</option><option value="TEL">Telefone</option></select></label>
          <label>Nome<input value={editServiceLabel} onChange={event => setEditServiceLabel(event.target.value)} /></label>
          <label className="wide">URI SIP<input value={editServiceSipUri} onChange={event => setEditServiceSipUri(event.target.value)} placeholder={editingService.legacy_rtsp ? 'Informe a URI SIP para migrar este rádio' : 'sip:...'} /></label>
          {editServiceKind === 'RADIO' && <label className="wide">Gateway<select value={editServiceGatewayId} onChange={event => setEditServiceGatewayId(event.target.value)}><option value="">Selecione</option>{gateways.map(gateway => <option value={gateway.id} key={gateway.id}>{gateway.label}</option>)}</select></label>}
        </div>
        <footer><button type="button" onClick={() => setEditingService(null)}>Cancelar</button><button type="button" className="primary" disabled={!editServiceSipUri.trim() || (editServiceKind === 'RADIO' && !editServiceGatewayId)} onClick={() => void saveServiceEdit()}>Salvar alterações</button></footer>
      </section>
    </div>}

    {deleteTarget && <div className="registry-modal-backdrop" onMouseDown={() => setDeleteTarget(null)}>
      <section className="registry-modal registry-confirm-modal" onMouseDown={event => event.stopPropagation()}>
        <div className="registry-confirm-icon"><AlertTriangle size={24} /></div>
        <div><span>Confirmar exclusão</span><h2>{deleteTarget.label}</h2><p>Esta ação remove o cadastro persistido. Gateways em uso por rádios não podem ser removidos.</p></div>
        <footer><button type="button" onClick={() => setDeleteTarget(null)}>Cancelar</button><button type="button" className="danger" onClick={() => void deleteConfirmed()}>Excluir definitivamente</button></footer>
      </section>
    </div>}

    <div style={{ display: 'none' }}>{gatewayOptions('')}</div>
  </main>
}
