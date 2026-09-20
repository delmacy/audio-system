import { Network, Server } from 'lucide-react'
import type { SimStatus, SimulatorMode } from '@/features/simulator/model'

export function RecorderFull({ mode, status }: { mode: SimulatorMode; status: SimStatus }) {
  const recording = mode === 'capture'
    ? 'Capturando do gravador corrente'
    : status === 'running' ? 'Gravando simulação' : 'Pronto para simulação'

  return <section className="recorder-column" aria-label="Gravador e Gateway">
    <div className="recorder-card central">
      <Server size={30} /><strong>Gravador</strong><small><i className="status-dot" />Online</small>
      <dl>
        <div><dt>IP</dt><dd>10.10.0.10</dd></div>
        <div><dt>RTSP</dt><dd>8554</dd></div>
        <div><dt>Status</dt><dd>{recording}</dd></div>
      </dl>
      <div className="health-list">
        <span><i />Ingestão RTSP OK</span>
        <span><i />Writer MXF OK</span>
        <span><i />Indexer OK</span>
        <span><i />File Manager OK</span>
      </div>
    </div>
    <div className="flow-line"><span>RTSP/RTP direto</span></div>
    <div className="recorder-card gateway">
      <Network size={28} /><strong>Gateway SIP</strong><small><i className="status-dot" />Online</small>
      <dl><div><dt>IP</dt><dd>10.10.0.20</dd></div><div><dt>SIP</dt><dd>5060</dd></div></dl>
      <p>Telefonia e rádio físico/legado passam por tradução para RTSP/RTP.</p>
    </div>
  </section>
}
