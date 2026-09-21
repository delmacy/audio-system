import { Activity, Cpu, FileAudio, HardDrive, Network, Phone, Radio, RadioTower, RefreshCw, Save, Server } from 'lucide-react'
import { useCallback, useEffect, useMemo, useState } from 'react'

type RecordingFileStatus = {
  kind: 'cwp' | 'radio' | 'telephone'
  directory: string
  file: string
  file_name: string
  partial: string
  lock: string
  exists: boolean
  size_bytes: number | null
  latest_file: string | null
  latest_file_path: string | null
  latest_size_bytes: number | null
}

type RecorderStatusPayload = {
  schema: string
  checked_utc: string
  runtime_status: 'recording' | 'online' | 'offline' | 'unconfigured'
  rtsp_reachable: boolean
  recorder: {
    ip: string | null
    rtsp_port: number | null
    rtsp_base_url: string | null
  }
  recording: {
    state: string
    is_recording: boolean
    run_id: string | null
    track_count: number
  }
  recording_layout: {
    root: string
    hierarchy: string[]
    categories: string[]
    files: {
      cwp: RecordingFileStatus
      radio: RecordingFileStatus
      telephone: RecordingFileStatus
    }
    settings: {
      telephone: {
        ringing_slots_per_phone: number
        calling_slots_per_phone: number
      }
      rotation_minutes: number
    }
  }
  telephone_capacity: {
    registered_phones: number
    ringing_slots_per_phone: number
    calling_slots_per_phone: number
    tracks_per_phone: number
    total_track_capacity: number
  }
  metrics: {
    disk: unknown
    cpu: unknown
    memory: unknown
    network: unknown
  }
}

async function responseJson<T>(response: Response) {
  const payload = await response.json().catch(() => null) as T | { detail?: string } | null
  if (!response.ok) {
    throw new Error(payload && typeof payload === 'object' && 'detail' in payload && payload.detail ? payload.detail : `HTTP ${response.status}`)
  }
  return payload as T
}

function formatBytes(value: number | null) {
  if (value == null) return '—'
  if (value < 1024) return value + ' B'
  if (value < 1024 ** 2) return (value / 1024).toFixed(1) + ' KB'
  if (value < 1024 ** 3) return (value / 1024 ** 2).toFixed(1) + ' MB'
  return (value / 1024 ** 3).toFixed(2) + ' GB'
}

function statusLabel(status: RecorderStatusPayload['runtime_status']) {
  if (status === 'recording') return 'Gravando'
  if (status === 'online') return 'Online'
  if (status === 'offline') return 'Offline'
  return 'Não configurado'
}

const FILE_META = {
  cwp: { title: 'CWP', detail: 'Uma trilha por CWP', icon: Server },
  radio: { title: 'Rádios', detail: 'Uma trilha por frequência ativa', icon: Radio },
  telephone: { title: 'Telefones', detail: 'Slots independentes de ringing e calling', icon: Phone },
} as const

export function RecorderStatusView() {
  const [data, setData] = useState<RecorderStatusPayload | null>(null)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [ringingSlots, setRingingSlots] = useState(5)
  const [callingSlots, setCallingSlots] = useState(4)
  const [rotationMinutes, setRotationMinutes] = useState(60)

  const load = useCallback(async () => {
    try {
      const next = await responseJson<RecorderStatusPayload>(
        await fetch('/api/recorder/status', { headers: { Accept: 'application/json' } }),
      )
      setData(next)
      setRingingSlots(next.recording_layout.settings.telephone.ringing_slots_per_phone)
      setCallingSlots(next.recording_layout.settings.telephone.calling_slots_per_phone)
      setRotationMinutes(next.recording_layout.settings.rotation_minutes)
      setError('')
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao consultar o gravador.')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
    const timer = window.setInterval(() => void load(), 3000)
    return () => window.clearInterval(timer)
  }, [load])

  const saveSettings = async () => {
    setSaving(true)
    setError('')
    try {
      await responseJson(await fetch('/api/recorder/settings', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({
          telephone: {
            ringing_slots_per_phone: ringingSlots,
            calling_slots_per_phone: callingSlots,
          },
          rotation_minutes: rotationMinutes,
        }),
      }))
      await load()
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha ao salvar configuração do gravador.')
    } finally {
      setSaving(false)
    }
  }

  const lastCheck = useMemo(() => {
    if (!data?.checked_utc) return '—'
    const date = new Date(data.checked_utc)
    return Number.isNaN(date.getTime()) ? data.checked_utc : date.toLocaleTimeString()
  }, [data?.checked_utc])

  const runtimeStatus = data?.runtime_status ?? 'offline'
  const files = data?.recording_layout.files
  const telephoneCapacity = data?.telephone_capacity

  return <main className="recorder-page">
    <header className="recorder-page-header">
      <div>
        <span className="registry-eyebrow">Operação do gravador</span>
        <h1>Gravador</h1>
        <p>Três MXF simultâneos: CWP, rádio e telefone, organizados por ano/mês/dia/categoria.</p>
      </div>
      <div className="recorder-header-actions">
        <span className={'recorder-live-state ' + runtimeStatus}><i />{statusLabel(runtimeStatus)}</span>
        <button type="button" onClick={() => void load()} disabled={loading}><RefreshCw size={14} />Atualizar</button>
      </div>
    </header>

    {error && <div className="registry-api-state error">
      <span>{error}</span>
      <button type="button" onClick={() => void load()}><RefreshCw size={14} />Tentar novamente</button>
    </div>}

    <section className="recorder-overview-grid">
      <article className="recorder-status-card primary">
        <div className="recorder-card-icon"><Activity size={20} /></div>
        <span>Estado operacional</span>
        <strong>{statusLabel(runtimeStatus)}</strong>
        <small>{data?.rtsp_reachable ? 'Porta RTSP acessível' : 'Porta RTSP não respondeu'}</small>
      </article>
      <article className="recorder-status-card">
        <div className="recorder-card-icon"><RadioTower size={20} /></div>
        <span>IP do gravador</span>
        <strong>{data?.recorder.ip ?? '—'}</strong>
        <small>{data?.recorder.rtsp_port ? 'RTSP :' + data.recorder.rtsp_port : 'Porta não configurada'}</small>
      </article>
      <article className="recorder-status-card">
        <div className="recorder-card-icon"><FileAudio size={20} /></div>
        <span>MXF simultâneos</span>
        <strong>3</strong>
        <small>CWP · Rádio · Telefone</small>
      </article>
      <article className="recorder-status-card">
        <div className="recorder-card-icon"><Phone size={20} /></div>
        <span>Capacidade telefônica</span>
        <strong>{telephoneCapacity?.total_track_capacity ?? 0}</strong>
        <small>{telephoneCapacity?.registered_phones ?? 0} telefones cadastrados</small>
      </article>
    </section>

    <section className="recorder-panel">
      <header>
        <div>
          <FileAudio size={18} />
          <div><strong>Arquivos selecionados para gravação</strong><small>Janela atual dentro do diretório operacional</small></div>
        </div>
      </header>
      <div className="recorder-three-files">
        {(['cwp', 'radio', 'telephone'] as const).map(kind => {
          const file = files?.[kind]
          const meta = FILE_META[kind]
          const Icon = meta.icon
          return <article key={kind} className="recorder-mxf-card">
            <div className="recorder-mxf-title">
              <span className={'recorder-mxf-icon ' + kind}><Icon size={17} /></span>
              <div><strong>{meta.title}</strong><small>{meta.detail}</small></div>
            </div>
            <div className="recorder-mxf-file">
              <span>MXF atual</span>
              <strong>{file?.file_name ?? '—'}</strong>
              <small>{file?.file ?? '—'}</small>
            </div>
            <div className="recorder-mxf-foot">
              <span className={file?.exists ? 'exists' : ''}><i />{file?.exists ? 'Arquivo criado' : 'Aguardando mídia'}</span>
              <span>{file?.exists ? formatBytes(file.size_bytes) : file?.latest_file ? 'Último: ' + file.latest_file : 'Sem arquivo anterior'}</span>
            </div>
          </article>
        })}
      </div>
    </section>

    <section className="recorder-panel">
      <header>
        <div>
          <HardDrive size={18} />
          <div><strong>Estrutura de armazenamento</strong><small>Raiz e hierarquia usadas pelo gravador</small></div>
        </div>
      </header>
      <div className="recorder-storage-layout">
        <div><span>Raiz</span><strong>{data?.recording_layout.root ?? 'recordings'}</strong></div>
        <code>
          recordings/<br />
          └─ ANO/<br />
          &nbsp;&nbsp;└─ MÊS/<br />
          &nbsp;&nbsp;&nbsp;&nbsp;└─ DIA/<br />
          &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;├─ cwp/<br />
          &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;├─ radio/<br />
          &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;└─ telephone/
        </code>
      </div>
    </section>

    <section className="recorder-panel">
      <header>
        <div>
          <Phone size={18} />
          <div><strong>Capacidade de telefonia</strong><small>Reserva de trilhas para evitar colisões de sessões simultâneas</small></div>
        </div>
      </header>
      <div className="recorder-phone-config">
        <label>
          Ringing por telefone
          <input type="number" min={1} max={128} value={ringingSlots} onChange={event => setRingingSlots(Number(event.target.value))} />
          <small>Slots simultâneos aguardando atendimento.</small>
        </label>
        <label>
          Calling por telefone
          <input type="number" min={1} max={128} value={callingSlots} onChange={event => setCallingSlots(Number(event.target.value))} />
          <small>Slots simultâneos de chamada estabelecida.</small>
        </label>
        <label>
          Rotação MXF
          <div className="recorder-input-unit"><input type="number" min={1} max={1440} value={rotationMinutes} onChange={event => setRotationMinutes(Number(event.target.value))} /><span>min</span></div>
          <small>Cria uma nova janela física mantendo a categoria.</small>
        </label>
        <div className="recorder-phone-capacity-summary">
          <span>Capacidade por telefone</span>
          <strong>{ringingSlots + callingSlots} trilhas</strong>
          <small>{ringingSlots} ringing + {callingSlots} calling</small>
        </div>
        <button type="button" className="recorder-save-config" onClick={() => void saveSettings()} disabled={saving}>
          <Save size={15} />Salvar configuração
        </button>
      </div>
      <div className="recorder-capacity-note">
        Cada slot é alocado em runtime para uma sessão/CWP correspondente. Uma frequência de rádio só gera mídia quando estiver ativa em algum CWP; ausência de atividade não produz gravação útil naquela trilha.
      </div>
    </section>

    <section className="recorder-panel">
      <header>
        <div>
          <Network size={18} />
          <div><strong>Conectividade</strong><small>Configuração e disponibilidade observadas</small></div>
        </div>
      </header>
      <div className="recorder-connectivity-grid">
        <div><span>Endereço RTSP</span><strong>{data?.recorder.rtsp_base_url ?? '—'}</strong></div>
        <div><span>Porta acessível</span><strong>{data?.rtsp_reachable ? 'Sim' : 'Não'}</strong></div>
        <div><span>Última consulta</span><strong>{lastCheck}</strong></div>
        <div><span>Gravando agora</span><strong>{data?.recording.is_recording ? 'Sim' : 'Não'}</strong></div>
      </div>
    </section>

    <section className="recorder-panel future">
      <header>
        <div>
          <Cpu size={18} />
          <div><strong>Telemetria do host</strong><small>Próxima etapa de observabilidade</small></div>
        </div>
      </header>
      <div className="recorder-future-grid">
        <div><HardDrive size={17} /><span>Disco</span><strong>Em breve</strong></div>
        <div><Cpu size={17} /><span>CPU</span><strong>Em breve</strong></div>
        <div><Activity size={17} /><span>Memória</span><strong>Em breve</strong></div>
        <div><Network size={17} /><span>Rede</span><strong>Em breve</strong></div>
      </div>
    </section>
  </main>
}
