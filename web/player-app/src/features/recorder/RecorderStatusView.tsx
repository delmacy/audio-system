import { Activity, Cpu, Database, FileAudio, HardDrive, Network, RadioTower, RefreshCw } from 'lucide-react'
import { useCallback, useEffect, useMemo, useState } from 'react'

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
    selected_file: string | null
    selected_file_path: string | null
    file_exists: boolean
    file_size_bytes: number | null
    shared_mxf: boolean
    track_count: number
    file_id: string | null
    generated_utc: string | null
  }
  metrics: {
    disk: unknown
    cpu: unknown
    memory: unknown
    network: unknown
  }
}

async function getRecorderStatus() {
  const response = await fetch('/api/recorder/status', { headers: { Accept: 'application/json' } })
  const payload = await response.json().catch(() => null) as RecorderStatusPayload | { detail?: string } | null
  if (!response.ok) {
    throw new Error(payload && 'detail' in payload && payload.detail ? payload.detail : `HTTP ${response.status}`)
  }
  return payload as RecorderStatusPayload
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

export function RecorderStatusView() {
  const [data, setData] = useState<RecorderStatusPayload | null>(null)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)

  const load = useCallback(async () => {
    try {
      const next = await getRecorderStatus()
      setData(next)
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

  const lastCheck = useMemo(() => {
    if (!data?.checked_utc) return '—'
    const date = new Date(data.checked_utc)
    return Number.isNaN(date.getTime()) ? data.checked_utc : date.toLocaleTimeString()
  }, [data?.checked_utc])

  const runtimeStatus = data?.runtime_status ?? 'offline'
  const recording = data?.recording

  return <main className="recorder-page">
    <header className="recorder-page-header">
      <div>
        <span className="registry-eyebrow">Operação do gravador</span>
        <h1>Gravador</h1>
        <p>Status observado do recorder host, arquivo MXF atual/mais recente e composição de tracks.</p>
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
        <span>Tracks no arquivo</span>
        <strong>{recording?.track_count ?? 0}</strong>
        <small>{recording?.shared_mxf ? 'MXF compartilhado' : 'Estado observado'}</small>
      </article>

      <article className="recorder-status-card">
        <div className="recorder-card-icon"><Database size={20} /></div>
        <span>Estado da mídia</span>
        <strong>{recording?.state ?? 'NO_RUN'}</strong>
        <small>{recording?.file_exists ? 'Arquivo encontrado no disco' : 'Sem arquivo disponível'}</small>
      </article>
    </section>

    <section className="recorder-panel">
      <header>
        <div>
          <FileAudio size={18} />
          <div><strong>Arquivo de gravação</strong><small>Arquivo apontado pelo run atual/mais recente</small></div>
        </div>
      </header>
      <div className="recorder-file-details">
        <div className="recorder-file-main">
          <span>MXF</span>
          <strong>{recording?.selected_file ?? 'Nenhum arquivo selecionado'}</strong>
          <small>{recording?.selected_file_path ?? 'Ainda não há um run operacional disponível.'}</small>
        </div>
        <dl>
          <div><dt>Tracks</dt><dd>{recording?.track_count ?? 0}</dd></div>
          <div><dt>Tamanho</dt><dd>{formatBytes(recording?.file_size_bytes ?? null)}</dd></div>
          <div><dt>Run</dt><dd>{recording?.run_id ?? '—'}</dd></div>
          <div><dt>File ID</dt><dd>{recording?.file_id ?? '—'}</dd></div>
        </dl>
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
        <div><span>Gravando agora</span><strong>{recording?.is_recording ? 'Sim' : 'Não'}</strong></div>
      </div>
    </section>

    <section className="recorder-panel future">
      <header>
        <div>
          <Cpu size={18} />
          <div><strong>Telemetria do host</strong><small>Espaço reservado para a próxima etapa de observabilidade</small></div>
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
