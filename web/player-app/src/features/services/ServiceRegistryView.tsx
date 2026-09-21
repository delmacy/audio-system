import { AlertTriangle, Monitor, Pencil, Phone, Plus, Radio, RefreshCw, Trash2, X } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'

type ApiCwp = {
  id: string
  label: string
  ip: string
  side: 'A' | 'B'
  enabled: boolean
  ip_source: 'auto' | 'manual'
}

type ApiService = {
  id: string
  kind: 'RADIO' | 'TEL'
  label: string
  endpoint: string
  enabled: boolean
}

type ConfigPayload = {
  schema: string
  network: { allocation: string; next_cwp_ip: string }
  cwps: ApiCwp[]
  services: ApiService[]
}

async function responseJson(response: Response) {
  const payload = await response.json().catch(() => null) as { detail?: string } | null
  if (!response.ok) throw new Error(payload?.detail || `HTTP ${response.status}`)
  return payload
}

export function ServiceRegistryView() {
  const [cwps, setCwps] = useState<ApiCwp[]>([])
  const [services, setServices] = useState<ApiService[]>([])
  const [nextIp, setNextIp] = useState('')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [cwpFormOpen, setCwpFormOpen] = useState(false)
  const [serviceFormOpen, setServiceFormOpen] = useState(false)
  const [cwpLabel, setCwpLabel] = useState('')
  const [cwpIp, setCwpIp] = useState('')
  const [cwpSide, setCwpSide] = useState<'A' | 'B'>('A')
  const [serviceKind, setServiceKind] = useState<'RADIO' | 'TEL'>('RADIO')
  const [serviceLabel, setServiceLabel] = useState('')
  const [serviceEndpoint, setServiceEndpoint] = useState('')
  const [editingCwp, setEditingCwp] = useState<ApiCwp | null>(null)
  const [editingService, setEditingService] = useState<ApiService | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<{ type: 'cwp' | 'service'; id: string; label: string } | null>(null)
  const [editCwpLabel, setEditCwpLabel] = useState('')
  const [editCwpIp, setEditCwpIp] = useState('')
  const [editCwpSide, setEditCwpSide] = useState<'A' | 'B'>('A')
  const [editServiceKind, setEditServiceKind] = useState<'RADIO' | 'TEL'>('RADIO')
  const [editServiceLabel, setEditServiceLabel] = useState('')
  const [editServiceEndpoint, setEditServiceEndpoint] = useState('')

  const stats = useMemo(() => ({
    cwps: cwps.length,
    radios: services.filter(service => service.kind === 'RADIO').length,
    telephones: services.filter(service => service.kind === 'TEL').length,
  }), [cwps, services])

  const load = async () => {
    setLoading(true)
    setError('')
    try {
      const response = await fetch('/api/config', { headers: { Accept: 'application/json' } })
      const payload = await responseJson(response) as ConfigPayload
      setCwps(payload.cwps)
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
      const response = await fetch('/api/network/next-ip', { headers: { Accept: 'application/json' } })
      const payload = await responseJson(response) as { ip: string }
      setNextIp(payload.ip)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao consultar próximo IP.')
    }
  }

  const addCwp = async () => {
    const label = cwpLabel.trim()
    if (!label) return
    setSaving(true)
    setError('')
    try {
      const response = await fetch('/api/cwps', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({ label, side: cwpSide, ip: cwpIp.trim() || null }),
      })
      await responseJson(response)
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
    const label = serviceLabel.trim()
    const endpoint = serviceEndpoint.trim()
    if (!label || !endpoint) return
    setSaving(true)
    setError('')
    try {
      const response = await fetch('/api/services', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({ kind: serviceKind, label, endpoint }),
      })
      await responseJson(response)
      setServiceLabel('')
      setServiceEndpoint('')
      setServiceKind('RADIO')
      setServiceFormOpen(false)
      await load()
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao cadastrar serviço.')
    } finally {
      setSaving(false)
    }
  }

  const startEditCwp = (item: ApiCwp) => {
    setEditingCwp(item)
    setEditCwpLabel(item.label)
    setEditCwpIp(item.ip)
    setEditCwpSide(item.side)
    setError('')
  }

  const saveCwpEdit = async () => {
    if (!editingCwp || !editCwpLabel.trim() || !editCwpIp.trim()) return
    setSaving(true)
    setError('')
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

  const startEditService = (item: ApiService) => {
    setEditingService(item)
    setEditServiceKind(item.kind)
    setEditServiceLabel(item.label)
    setEditServiceEndpoint(item.endpoint)
    setError('')
  }

  const saveServiceEdit = async () => {
    if (!editingService || !editServiceLabel.trim() || !editServiceEndpoint.trim()) return
    setSaving(true)
    setError('')
    try {
      await responseJson(await fetch('/api/services/' + encodeURIComponent(editingService.id), {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({
          kind: editServiceKind,
          label: editServiceLabel.trim(),
          endpoint: editServiceEndpoint.trim(),
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

  const removeCwp = async (item: ApiCwp) => {
    setSaving(true)
    setError('')
    try {
      await responseJson(await fetch('/api/cwps/' + encodeURIComponent(item.id), { method: 'DELETE' }))
      await load()
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao excluir CWP.')
    } finally {
      setSaving(false)
    }
  }

  const removeService = async (item: ApiService) => {
    setSaving(true)
    setError('')
    try {
      await responseJson(await fetch('/api/services/' + encodeURIComponent(item.id), { method: 'DELETE' }))
      await load()
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao excluir serviço.')
    } finally {
      setSaving(false)
    }
  }

  return <main className="registry-page">
    <header className="registry-page-header">
      <div>
        <span className="registry-eyebrow">Configuração persistente · SQLite</span>
        <h1>Serviços & CWP</h1>
        <p>CWP, rádios e ramais cadastrados aqui permanecem disponíveis após reiniciar navegador, backend ou computador.</p>
      </div>
      <div className="registry-summary">
        <span><strong>{stats.cwps}</strong>CWP</span>
        <span><strong>{stats.radios}</strong>Rádios</span>
        <span><strong>{stats.telephones}</strong>Telefones</span>
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
        <button type="button" className="registry-add-button" onClick={() => void openCwpForm()}>
          <Plus size={16} />Incluir CWP
        </button>
      </header>

      {cwpFormOpen && <div className="registry-inline-form">
        <label>Nome<input value={cwpLabel} onChange={event => setCwpLabel(event.target.value)} placeholder="CWP-003" /></label>
        <label>IP
          <input value={cwpIp} onChange={event => setCwpIp(event.target.value)} placeholder={nextIp ? 'Auto: ' + nextIp : 'Automático'} />
          <small>Vazio = próximo IP livre; preenchido = IP manual.</small>
        </label>
        <label>Lado<select value={cwpSide} onChange={event => setCwpSide(event.target.value as 'A' | 'B')}><option value="A">A</option><option value="B">B</option></select></label>
        <div>
          <button type="button" onClick={() => setCwpFormOpen(false)}>Cancelar</button>
          <button type="button" className="primary" onClick={() => void addCwp()} disabled={saving || !cwpLabel.trim()}>Adicionar</button>
        </div>
      </div>}

      <div className="registry-list">
        {cwps.map(cwp => <article className="registry-row" key={cwp.id}>
          <span className="registry-row-icon"><Monitor size={17} /></span>
          <div className="registry-row-main">
            <strong>{cwp.label}</strong>
            <small>{cwp.ip}</small>
          </div>
          <span className="registry-row-meta">Lado {cwp.side}</span>
          <span className={'registry-ip-source ' + cwp.ip_source}>{cwp.ip_source === 'auto' ? 'AUTO IP' : 'MANUAL'}</span>
          <span className="registry-row-state"><i />{cwp.enabled ? 'Ativo' : 'Inativo'}</span>
          <div className="registry-row-actions">
            <button type="button" className="registry-edit" disabled={saving} onClick={() => startEditCwp(cwp)} aria-label={'Editar ' + cwp.label}>
              <Pencil size={14} />
            </button>
            <button type="button" className="registry-delete" disabled={saving} onClick={() => setDeleteTarget({ type: 'cwp', id: cwp.id, label: cwp.label })} aria-label={'Excluir ' + cwp.label}>
              <Trash2 size={15} />
            </button>
          </div>
        </article>)}
        {!loading && cwps.length === 0 && <div className="registry-empty">Nenhum CWP cadastrado.</div>}
      </div>
    </section>

    <section className="registry-section">
      <header>
        <div>
          <span className="registry-section-icon"><Radio size={17} /></span>
          <div><strong>Serviços</strong><small>Rádios e ramais persistidos no banco</small></div>
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
          <button type="button" className="primary" onClick={() => void addService()} disabled={saving || !serviceLabel.trim() || !serviceEndpoint.trim()}>Adicionar</button>
        </div>
      </div>}

      <div className="registry-list">
        {services.map(service => <article className="registry-row" key={service.id}>
          <span className={'registry-row-icon ' + service.kind.toLowerCase()}>
            {service.kind === 'RADIO' ? <Radio size={17} /> : <Phone size={17} />}
          </span>
          <div className="registry-row-main">
            <strong>{service.label}</strong>
            <small>{service.endpoint}</small>
          </div>
          <span className={'registry-kind ' + service.kind.toLowerCase()}>{service.kind === 'RADIO' ? 'RÁDIO' : 'TEL'}</span>
          <span className="registry-row-meta">Global</span>
          <span className="registry-row-state"><i />{service.enabled ? 'Ativo' : 'Inativo'}</span>
          <div className="registry-row-actions">
            <button type="button" className="registry-edit" disabled={saving} onClick={() => startEditService(service)} aria-label={'Editar ' + service.label}>
              <Pencil size={14} />
            </button>
            <button type="button" className="registry-delete" disabled={saving} onClick={() => setDeleteTarget({ type: 'service', id: service.id, label: service.label })} aria-label={'Excluir ' + service.label}>
              <Trash2 size={15} />
            </button>
          </div>
        </article>)}
        {!loading && services.length === 0 && <div className="registry-empty">Nenhum serviço cadastrado.</div>}
      </div>
    </section>

    {editingCwp && <div className="registry-modal-backdrop" role="presentation" onMouseDown={() => setEditingCwp(null)}>
      <section className="registry-modal" role="dialog" aria-modal="true" aria-label={'Editar ' + editingCwp.label} onMouseDown={event => event.stopPropagation()}>
        <header>
          <div><span>Editar CWP</span><strong>{editingCwp.label}</strong></div>
          <button type="button" onClick={() => setEditingCwp(null)} aria-label="Fechar"><X size={17} /></button>
        </header>
        <div className="registry-modal-form">
          <label>Nome<input value={editCwpLabel} onChange={event => setEditCwpLabel(event.target.value)} /></label>
          <label>IP<input value={editCwpIp} onChange={event => setEditCwpIp(event.target.value)} /></label>
          <label>Lado<select value={editCwpSide} onChange={event => setEditCwpSide(event.target.value as 'A' | 'B')}><option value="A">A</option><option value="B">B</option></select></label>
        </div>
        <footer>
          <button type="button" onClick={() => setEditingCwp(null)}>Cancelar</button>
          <button type="button" className="primary" disabled={saving || !editCwpLabel.trim() || !editCwpIp.trim()} onClick={() => void saveCwpEdit()}>Salvar alterações</button>
        </footer>
      </section>
    </div>}

    {editingService && <div className="registry-modal-backdrop" role="presentation" onMouseDown={() => setEditingService(null)}>
      <section className="registry-modal" role="dialog" aria-modal="true" aria-label={'Editar ' + editingService.label} onMouseDown={event => event.stopPropagation()}>
        <header>
          <div><span>Editar serviço</span><strong>{editingService.label}</strong></div>
          <button type="button" onClick={() => setEditingService(null)} aria-label="Fechar"><X size={17} /></button>
        </header>
        <div className="registry-modal-form">
          <label>Tipo<select value={editServiceKind} onChange={event => setEditServiceKind(event.target.value as 'RADIO' | 'TEL')}><option value="RADIO">Rádio</option><option value="TEL">Telefone</option></select></label>
          <label>Nome<input value={editServiceLabel} onChange={event => setEditServiceLabel(event.target.value)} /></label>
          <label className="wide">Endpoint<input value={editServiceEndpoint} onChange={event => setEditServiceEndpoint(event.target.value)} /></label>
        </div>
        <footer>
          <button type="button" onClick={() => setEditingService(null)}>Cancelar</button>
          <button type="button" className="primary" disabled={saving || !editServiceLabel.trim() || !editServiceEndpoint.trim()} onClick={() => void saveServiceEdit()}>Salvar alterações</button>
        </footer>
      </section>
    </div>}

    {deleteTarget && <div className="registry-modal-backdrop" role="presentation" onMouseDown={() => setDeleteTarget(null)}>
      <section className="registry-modal registry-confirm-modal" role="alertdialog" aria-modal="true" aria-label={'Confirmar exclusão de ' + deleteTarget.label} onMouseDown={event => event.stopPropagation()}>
        <div className="registry-confirm-icon"><AlertTriangle size={24} /></div>
        <div>
          <span>Confirmar exclusão</span>
          <h2>{deleteTarget.label}</h2>
          <p>Esta ação remove o cadastro persistido do sistema. Deseja continuar?</p>
        </div>
        <footer>
          <button type="button" onClick={() => setDeleteTarget(null)}>Cancelar</button>
          <button type="button" className="danger" disabled={saving} onClick={() => {
            const target = deleteTarget
            setDeleteTarget(null)
            if (target.type === 'cwp') {
              const item = cwps.find(cwp => cwp.id === target.id)
              if (item) void removeCwp(item)
            } else {
              const item = services.find(service => service.id === target.id)
              if (item) void removeService(item)
            }
          }}>Excluir definitivamente</button>
        </footer>
      </section>
    </div>}
  </main>
}
