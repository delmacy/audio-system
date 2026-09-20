import { Activity, AlertTriangle, ChevronDown, Database, Users } from 'lucide-react'

export function EventsBlock({ events }: { events: string[] }) {
  return <aside className="sim-right-panel">
    <section className="live-status-card">
      <h2>Live Status</h2>
      <div className="live-row"><Users size={21} /><span>Sessões</span><strong>4</strong></div>
      <div className="live-row"><Activity size={21} /><span>RTP streams</span><strong>16</strong></div>
      <div className="live-row"><Database size={21} /><span>Recorder</span><strong>OK</strong></div>
      <div className="live-row"><AlertTriangle size={21} /><span>Falhas</span><strong>0</strong></div>
    </section>

    <section className="event-console-card">
      <header><h2>Eventos Recentes</h2><button type="button">Todos <ChevronDown size={14} /></button></header>
      <div className="event-list">
        {events.map((event, index) => <div key={event + index} className="event-row">
          <span>{`22:${String(45 - index).padStart(2, '0')}`}</span>
          <i className="status-dot" />
          <p>{event}</p>
        </div>)}
      </div>
    </section>

    <section className="metrics-card">
      <h2>Métricas</h2>
      <label>CPU Recorder <span>32%</span><progress value="32" max="100" /></label>
      <label>Rede ingresso <span>48%</span><progress value="48" max="100" /></label>
      <label>Disco <span>27%</span><progress value="27" max="100" /></label>
    </section>
  </aside>
}
