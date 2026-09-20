import { Activity, Database, HardDrive, Network } from 'lucide-react'

const metrics = [
  { icon: Activity, label: 'CPU', value: 32, unit: '%', detail: 'Recorder engine' },
  { icon: Network, label: 'Rede ingresso', value: 48, unit: '%', detail: 'RTP/RTSP' },
  { icon: HardDrive, label: 'Disco', value: 42, unit: '%', detail: '420 GB / 1 TB' },
  { icon: Database, label: 'Indexação', value: 97, unit: '%', detail: 'SQLite / MXF' },
]

export function RecorderMeasurementView() {
  return <div className="recorder-view-body">
    <section className="recorder-measure-grid">
      {metrics.map(({ icon: Icon, label, value, unit, detail }) => <article key={label} className="recorder-measure-card">
        <Icon size={24} /><span>{label}</span><strong>{value}{unit}</strong><small>{detail}</small><progress value={value} max="100" />
      </article>)}
    </section>
    <section className="recorder-core-grid">
      <article className="recorder-core-card"><h3>Qualidade de gravação</h3><dl><div><dt>Streams esperados</dt><dd>16</dd></div><div><dt>Streams ativos</dt><dd>16</dd></div><div><dt>Gaps não esperados</dt><dd>0</dd></div><div><dt>Jitter médio</dt><dd>2.1 ms</dd></div></dl></article>
      <article className="recorder-core-card"><h3>Armazenamento</h3><dl><div><dt>Escrita</dt><dd>8.4 MB/s</dd></div><div><dt>Arquivos abertos</dt><dd>1</dd></div><div><dt>Último split</dt><dd>22:00</dd></div><div><dt>Indexer lag</dt><dd>0.8 s</dd></div></dl></article>
    </section>
  </div>
}
