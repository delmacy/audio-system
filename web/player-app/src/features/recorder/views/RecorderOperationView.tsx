import { RecorderFull } from '@/representations/recorder'
import type { SimStatus, SimulatorMode } from '@/features/simulator/model'

export function RecorderOperationView({ mode, status }: { mode: SimulatorMode; status: SimStatus }) {
  return <div className="recorder-view-body">
    <section className="recorder-primary-panel">
      <RecorderFull mode={mode} status={status} displayName="Recorder operacional" />
    </section>
    <section className="recorder-core-grid">
      <article className="recorder-core-card"><h3>Pipeline</h3><div className="health-list big"><span><i />RTSP Ingest OK</span><span><i />RTP Media Engine OK</span><span><i />MXF Writer OK</span><span><i />File Manager OK</span><span><i />SQLite Indexer OK</span><span><i />Event Bus OK</span></div></article>
      <article className="recorder-core-card"><h3>Sessão corrente</h3><dl><div><dt>Streams</dt><dd>16</dd></div><div><dt>Arquivo</dt><dd>MXF fechado</dd></div><div><dt>Janela</dt><dd>60 min</dd></div><div><dt>Modo</dt><dd>{mode === 'capture' ? 'Captura' : 'Simulação'}</dd></div></dl></article>
    </section>
  </div>
}
