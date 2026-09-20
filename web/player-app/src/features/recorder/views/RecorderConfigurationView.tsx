import { Save } from 'lucide-react'
import { useState } from 'react'
import { DEMO_RECORDER, type RecorderConfig } from '../model'

export function RecorderConfigurationView() {
  const [draft, setDraft] = useState<RecorderConfig>(DEMO_RECORDER)

  return <div className="recorder-view-body">
    <section className="recorder-config-panel">
      <header><div><h2>Configuração do gravador</h2><p>Parâmetros estruturais exclusivos do core de gravação. Gateway SIP é configurado como entidade independente.</p></div></header>
      <div className="recorder-config-grid">
        <label>Nome<input value={draft.name} onChange={e => setDraft({ ...draft, name: e.target.value })} /></label>
        <label>IP<input value={draft.ip} onChange={e => setDraft({ ...draft, ip: e.target.value })} /></label>
        <label>Porta RTSP<input type="number" value={draft.rtspPort} onChange={e => setDraft({ ...draft, rtspPort: Number(e.target.value) })} /></label>
        <label>Split (min)<input type="number" value={draft.splitMinutes} onChange={e => setDraft({ ...draft, splitMinutes: Number(e.target.value) })} /></label>
        <label>Writer<input value={draft.writer} onChange={e => setDraft({ ...draft, writer: e.target.value })} /></label>
        <label>Codec<input value={draft.codec} onChange={e => setDraft({ ...draft, codec: e.target.value })} /></label>
        <label>Storage total (GB)<input type="number" value={draft.storageTotalGb} onChange={e => setDraft({ ...draft, storageTotalGb: Number(e.target.value) })} /></label>
        <label>Streams esperados<input type="number" value={draft.streams} onChange={e => setDraft({ ...draft, streams: Number(e.target.value) })} /></label>
      </div>
      <div className="recorder-config-actions"><button type="button"><Save size={16} />Salvar configuração</button></div>
    </section>
  </div>
}
