import { useState } from 'react'
import { Activity, Settings2, Server } from 'lucide-react'
import { RecorderOperationView } from './RecorderOperationView'
import { RecorderMeasurementView } from './RecorderMeasurementView'
import { RecorderConfigurationView } from './RecorderConfigurationView'
import type { SimStatus, SimulatorMode } from '@/features/simulator/model'

type RecorderTab = 'operation' | 'measurement' | 'configuration'

export function RecorderWorkspaceView({ mode, status }: { mode: SimulatorMode; status: SimStatus }) {
  const [tab, setTab] = useState<RecorderTab>('operation')

  return <main className="recorder-workspace-main">
    <header className="recorder-workspace-header">
      <div><span>Core de gravação</span><h1>Gravador</h1><p>Operação, medição e configuração separadas para preservar contexto e segurança operacional.</p></div>
      <div className="recorder-connected"><i className="status-dot" />Recorder<span>10.10.0.10</span></div>
    </header>

    <nav className="recorder-tabs" aria-label="Views do gravador">
      <button type="button" className={tab === 'operation' ? 'active' : ''} onClick={() => setTab('operation')}><Server size={17} />Operação</button>
      <button type="button" className={tab === 'measurement' ? 'active' : ''} onClick={() => setTab('measurement')}><Activity size={17} />Medição</button>
      <button type="button" className={tab === 'configuration' ? 'active' : ''} onClick={() => setTab('configuration')}><Settings2 size={17} />Configuração</button>
    </nav>

    {tab === 'operation' && <RecorderOperationView mode={mode} status={status} />}
    {tab === 'measurement' && <RecorderMeasurementView />}
    {tab === 'configuration' && <RecorderConfigurationView />}
  </main>
}
