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

type ApiRps = {
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
  gateways: ApiRps[]
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

function deriveSipUser(label: string) {
  const matches = label.match(/\d+(?:\.\d+)*/g)
  if (!matches?.length) return ''
  return matches[matches.length - 1].replace(/\D/g, '')
}

function previewSipUri(label: string, rps?: ApiRps) {
  const user = deriveSipUser(label)
  if (!user || !rps) return ''
  return `sip:${user}@${rps.ip}:${rps.sip_port}`
}

export function ServiceRegistryView() {
  const [cwps, setCwps] = useState<ApiCwp[]>([])
  const [rpsList, setRpsList] = useState<ApiRps[]>([])
  const [services, setServices] = useState<ApiService[]>([])
  const [nextIp, setNextIp] = useState('')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const [cwpFormOpen, setCwpFormOpen] = useState(false)
  const [serviceFormOpen, setServiceFormOpen] = useState(false)
  const [rpsFormOpen, setRpsFormOpen] = useState(false)

  const [cwpLabel, setCwpLabel] = useState('')
  const [cwpIp, setCwpIp] = useState('')
  const [cwpSide, setCwpSide] = useState<'A' | 'B'>('A')

  const [serviceKind, setServiceKind] = useState<'RADIO' | 'TEL'>('RADIO')
  const [serviceLabel, setServiceLabel] = useState('')
  const [serviceRpsId, setServiceRpsId] = useState('')

  const [rpsLabel, setRpsLabel] = useState('')
  const [rpsTrunkIp, setRpsTrunkIp] = useState('')
  const [rpsSipPort, setRpsSipPort] = useState('5060')
  const [rpsRtspBaseUrl, setRpsRtspBaseUrl] = useState('')

  const [editingCwp, setEditingCwp] = useState<ApiCwp | null>(null)
  const [editingService, setEditingService] = useState<ApiService | null>(null)
  const [editingRps, setEditingRps] = useState<ApiRps | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<DeleteTarget | null>(null)

  const [editCwpLabel, setEditCwpLabel] = useState('')
  const [editCwpIp, setEditCwpIp] = useState('')
  const [editCwpSide, setEditCwpSide] = useState<'A' | 'B'>('A')

  const [editServiceKind, setEditServiceKind] = useState<'RADIO' | 'TEL'>('RADIO')
  const [editServiceLabel, setEditServiceLabel] = useState('')
  const [editServiceRpsId, setEditServiceRpsId] = useState('')

  const [editRpsLabel, setEditRpsLabel] = useState('')
  const [editRpsTrunkIp, setEditRpsTrunkIp] = useState('')
  const [editRpsSipPort, setEditRpsSipPort] = useState('5060')
  const [editRpsRtspBaseUrl, setEditRpsRtspBaseUrl] = useState('')

  const stats = useMemo(() => ({
    cwps: cwps.length,
    radios: services.filter(service => service.kind === 'RADIO').length,
    telephones: services.filter(service => service.kind === 'TEL').length,
    rps: rpsList.length,
  }), [cwps, rpsList, services])

  const selectedRps = rpsList.find(item => item.id === serviceRpsId)
  const serviceSipPreview = previewSipUri(serviceLabel, selectedRps)
  const selectedEditRps = rpsList.find(item => item.id === editServiceRpsId)
  const editServiceSipPreview = previewSipUri(editServiceLabel, selectedEditRps)

  const load = async () => {
    setLoading(true)
    setError('')
    try {
      const payload = await responseJson(await fetch('/api/config', { headers: { Accept: 'application/json' } })) as ConfigPayload
      setCwps(payload.cwps)
      setRpsList(payload.gateways ?? [])
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
    if (!serviceLabel.trim() || !serviceRpsId || !deriveSipUser(serviceLabel)) return
    setSaving(true)
    setError('')
    try {
      await responseJson(await fetch('/api/services', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({
          kind: serviceKind,
          label: serviceLabel.trim(),
          gateway_id: serviceRpsId,
        }),
      }))
      setServiceLabel('')
      setServiceKind('RADIO')
      setServiceRpsId('')
      setServiceFormOpen(false)
      await load()
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao cadastrar serviço.')
    } finally {
      setSaving(false)
    }
  }

  const addRps = async () => {
    if (!rpsLabel.trim() || !rpsTrunkIp.trim() || !rpsRtspBaseUrl.trim()) return
    setSaving(true)
    setError('')
    try {
      await responseJson(await fetch('/api/gateways', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({
          label: rpsLabel.trim(),
          ip: rpsTrunkIp.trim(),
          sip_port: Number(rpsSipPort),
          rtsp_base_url: rpsRtspBaseUrl.trim(),
        }),
      }))
      setRpsLabel('')
      setRpsTrunkIp('')
      setRpsSipPort('5060')
      setRpsRtspBaseUrl('')
      setRpsFormOpen(false)
      await load()
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao cadastrar RPS.')
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
    setEditServiceRpsId(item.gateway_id ?? '')
  }

  const startEditRps = (item: ApiRps) => {
    setEditingRps(item)
    setEditRpsLabel(item.label)
    setEditRpsTrunkIp(item.ip)
    setEditRpsSipPort(String(item.sip_port))
    setEditRpsRtspBaseUrl(item.rtsp_base_url)
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
    if (!editingService || !editServiceLabel.trim() || !editServiceRpsId || !deriveSipUser(editServiceLabel)) return
    setSaving(true)
    try {
      await responseJson(await fetch('/api/services/' + encodeURIComponent(editingService.id), {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({
          kind: editServiceKind,
          label: editServiceLabel.trim(),
          gateway_id: editServiceRpsId,
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

  const saveRpsEdit = async () => {
    if (!editingRps || !editRpsLabel.trim() || !editRpsTrunkIp.trim() || !editRpsRtspBaseUrl.trim()) return
    setSaving(true)
    try {
      await responseJson(await fetch('/api/gateways/' + encodeURIComponent(editingRps.id), {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({
          label: editRpsLabel.trim(),
          ip: editRpsTrunkIp.trim(),
          sip_port: Number(editRpsSipPort),
          rtsp_base_url: editRpsRtspBaseUrl.trim(),
        }),
      }))
      setEditingRps(null)
      await load()
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao editar RPS.')
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

  return <main className="registry-page">
    <header className="registry-page-header">
      <div>
        <span className="registry-eyebrow">Configuração persistente · SQLite</span>
        <h1>Serviços & CWP</h1>
        <p>As URIs SIP são geradas automaticamente a partir do ramal/frequência e do tronco configurado no RPS.</p>
      </div>
      <div className="registry-summary">
        <span><strong>{stats.cwps}</strong>CWP</span>
        <span><strong>{stats.radios}</strong>Rádios</span>
        <span><strong>{stats.telephones}</strong>Telefones</span>
        <span><strong>{stats.rps}</strong>RPS</span>
      </div>
    </header>

    {(loading || error) && <div className={'registry-api-state' + (error ? ' error' : '')}>
      <span>{loading ? 'Carregando configuração…' : error}</span>
      {!loading && <button type="button" onClick={() => void load()}><RefreshCw size={14} />Tentar novamente</button>}
    </div>}

    <section className="registry-section">
      <header>
        <div><span className="registry-section-icon"><Monitor size={17} /></span><div><strong>CWP</strong><small>Consoles persistidos no banco</small></div></div>
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
        <div><span className="registry-section-icon"><ArrowRightLeft size={17} /></span><div><strong>RPS · RTSP Proxy</strong><small>Configura o tronco SIP e o destino RTSP do gravador</small></div></div>
        <button type="button" className="registry-add-button" onClick={() => setRpsFormOpen(value => !value)}><Plus size={16} />Incluir RPS</button>
      </header>
      {rpsFormOpen && <div className="registry-inline-form gateway">
        <label>Nome<input value={rpsLabel} onChange={event => setRpsLabel(event.target.value)} placeholder="RPS principal" /></label>
        <label>IP do tronco<input value={rpsTrunkIp} onChange={event => setRpsTrunkIp(event.target.value)} placeholder="10.10.0.20" /></label>
        <label>Porta SIP<input type="number" value={rpsSipPort} onChange={event => setRpsSipPort(event.target.value)} /></label>
        <label>Destino RTSP<input value={rpsRtspBaseUrl} onChange={event => setRpsRtspBaseUrl(event.target.value)} placeholder="rtsp://10.10.0.10:8554" /></label>
        <div><button type="button" onClick={() => setRpsFormOpen(false)}>Cancelar</button><button type="button" className="primary" onClick={() => void addRps()} disabled={saving || !rpsLabel.trim() || !rpsTrunkIp.trim() || !rpsRtspBaseUrl.trim()}>Adicionar</button></div>
      </div>}
      <div className="registry-list">
        {rpsList.map(rps => <article className="registry-row" key={rps.id}>
          <span className="registry-row-icon gateway"><ArrowRightLeft size={17} /></span>
          <div className="registry-row-main"><strong>{rps.label}</strong><small>Tronco {rps.ip}:{rps.sip_port}</small></div>
          <span className="registry-kind gateway">RPS</span>
          <span className="registry-row-meta registry-row-rtsp">{rps.rtsp_base_url}</span>
          <span className="registry-row-state"><i />{rps.enabled ? 'Ativo' : 'Inativo'}</span>
          <div className="registry-row-actions">
            <button type="button" className="registry-edit" onClick={() => startEditRps(rps)}><Pencil size={14} /></button>
            <button type="button" className="registry-delete" onClick={() => setDeleteTarget({ type: 'gateway', id: rps.id, label: rps.label })}><Trash2 size={15} /></button>
          </div>
        </article>)}
      </div>
    </section>

    <section className="registry-section">
      <header>
        <div><span className="registry-section-icon"><Radio size={17} /></span><div><strong>Serviços SIP</strong><small>Informe somente o serviço e o RPS; a URI é gerada automaticamente</small></div></div>
        <button type="button" className="registry-add-button" onClick={() => setServiceFormOpen(value => !value)}><Plus size={16} />Incluir serviço</button>
      </header>
      {serviceFormOpen && <div className="registry-inline-form service sip-service">
        <label>Tipo<select value={serviceKind} onChange={event => setServiceKind(event.target.value as 'RADIO' | 'TEL')}><option value="RADIO">Rádio</option><option value="TEL">Telefone</option></select></label>
        <label>Nome / frequência / ramal<input value={serviceLabel} onChange={event => setServiceLabel(event.target.value)} placeholder={serviceKind === 'RADIO' ? 'TWR 121.500' : 'TEL-050'} /></label>
        <label>RPS<select value={serviceRpsId} onChange={event => setServiceRpsId(event.target.value)}><option value="">Selecione</option>{rpsList.map(rps => <option value={rps.id} key={rps.id}>{rps.label}</option>)}</select></label>
        <label>URI SIP gerada<input value={serviceSipPreview} readOnly placeholder="Será gerada automaticamente" /><small>{deriveSipUser(serviceLabel) ? 'Identificador SIP: ' + deriveSipUser(serviceLabel) : 'Inclua um número no nome.'}</small></label>
        <div><button type="button" onClick={() => setServiceFormOpen(false)}>Cancelar</button><button type="button" className="primary" onClick={() => void addService()} disabled={saving || !serviceLabel.trim() || !serviceRpsId || !deriveSipUser(serviceLabel)}>Adicionar</button></div>
      </div>}
      <div className="registry-list">
        {services.map(service => <article className={'registry-row' + (service.legacy_rtsp ? ' legacy' : '')} key={service.id}>
          <span className={'registry-row-icon ' + service.kind.toLowerCase()}>{service.kind === 'RADIO' ? <Radio size={17} /> : <Phone size={17} />}</span>
          <div className="registry-row-main"><strong>{service.label}</strong><small>{service.sip_uri ?? service.endpoint}</small></div>
          <span className={'registry-kind ' + service.kind.toLowerCase()}>{service.kind === 'RADIO' ? 'RÁDIO SIP' : 'TEL SIP'}</span>
          <span className="registry-row-meta">{service.gateway_label ?? (service.legacy_rtsp ? 'Legado RTSP' : 'Sem RPS')}</span>
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

    {editingRps && <div className="registry-modal-backdrop" onMouseDown={() => setEditingRps(null)}>
      <section className="registry-modal" onMouseDown={event => event.stopPropagation()}>
        <header><div><span>Editar RPS</span><strong>{editingRps.label}</strong></div><button type="button" onClick={() => setEditingRps(null)}><X size={17} /></button></header>
        <div className="registry-modal-form">
          <label>Nome<input value={editRpsLabel} onChange={event => setEditRpsLabel(event.target.value)} /></label>
          <label>IP do tronco<input value={editRpsTrunkIp} onChange={event => setEditRpsTrunkIp(event.target.value)} /></label>
          <label>Porta SIP<input type="number" value={editRpsSipPort} onChange={event => setEditRpsSipPort(event.target.value)} /></label>
          <label>Destino RTSP<input value={editRpsRtspBaseUrl} onChange={event => setEditRpsRtspBaseUrl(event.target.value)} /></label>
        </div>
        <footer><button type="button" onClick={() => setEditingRps(null)}>Cancelar</button><button type="button" className="primary" onClick={() => void saveRpsEdit()}>Salvar alterações</button></footer>
      </section>
    </div>}

    {editingService && <div className="registry-modal-backdrop" onMouseDown={() => setEditingService(null)}>
      <section className="registry-modal" onMouseDown={event => event.stopPropagation()}>
        <header><div><span>Editar serviço SIP</span><strong>{editingService.label}</strong></div><button type="button" onClick={() => setEditingService(null)}><X size={17} /></button></header>
        <div className="registry-modal-form">
          <label>Tipo<select value={editServiceKind} onChange={event => setEditServiceKind(event.target.value as 'RADIO' | 'TEL')}><option value="RADIO">Rádio</option><option value="TEL">Telefone</option></select></label>
          <label>Nome / frequência / ramal<input value={editServiceLabel} onChange={event => setEditServiceLabel(event.target.value)} /></label>
          <label>RPS<select value={editServiceRpsId} onChange={event => setEditServiceRpsId(event.target.value)}><option value="">Selecione</option>{rpsList.map(rps => <option value={rps.id} key={rps.id}>{rps.label}</option>)}</select></label>
          <label>URI SIP gerada<input value={editServiceSipPreview} readOnly placeholder="Será gerada automaticamente" /></label>
        </div>
        <footer><button type="button" onClick={() => setEditingService(null)}>Cancelar</button><button type="button" className="primary" disabled={!editServiceLabel.trim() || !editServiceRpsId || !deriveSipUser(editServiceLabel)} onClick={() => void saveServiceEdit()}>Salvar alterações</button></footer>
      </section>
    </div>}

    {deleteTarget && <div className="registry-modal-backdrop" onMouseDown={() => setDeleteTarget(null)}>
      <section className="registry-modal registry-confirm-modal" onMouseDown={event => event.stopPropagation()}>
        <div className="registry-confirm-icon"><AlertTriangle size={24} /></div>
        <div><span>Confirmar exclusão</span><h2>{deleteTarget.label}</h2><p>Esta ação remove o cadastro persistido. RPS em uso por serviços não pode ser removido.</p></div>
        <footer><button type="button" onClick={() => setDeleteTarget(null)}>Cancelar</button><button type="button" className="danger" onClick={() => void deleteConfirmed()}>Excluir definitivamente</button></footer>
      </section>
    </div>}
  </main>
}
