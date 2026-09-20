import { useState } from 'react'
import { TooltipProvider } from '@/components/ui/tooltip'
import { AppSidebar } from '@/app/AppSidebar'
import { PlayerView } from '@/features/player/PlayerView'
import { SimulatorView } from '@/features/simulator/views/SimulatorView'
import { WorkspaceView } from '@/features/simulator/views/WorkspaceView'
import { RecorderWorkspaceView } from '@/features/recorder/views/RecorderWorkspaceView'
import { ComponentCatalogView } from '@/features/components/ComponentCatalogView'
import type { MainView, SimulatorMode, SimStatus } from '@/features/simulator/model'
import { useTimelineStore } from '@/timeline-store'
import './App.css'

const INITIAL_EVENTS = [
  'Gravador pronto em 10.10.0.10',
  'Gateway SIP online em 10.10.0.20',
  'CWP-A01 conectado',
  'CWP-A02 conectado',
  'CWP-B01 conectado',
  'CWP-B02 conectado',
  'Modo Simulação de Teste ativado',
]

function App() {
  const sidebarCollapsed = useTimelineStore(state => state.sidebarCollapsed)
  const setSidebarCollapsed = useTimelineStore(state => state.setSidebarCollapsed)
  const setPanel = useTimelineStore(state => state.setPanel)
  const [activeView, setActiveView] = useState<MainView>('simulator')
  const [simulatorMode, setSimulatorMode] = useState<SimulatorMode>('simulation')
  const [simulatorStatus, setSimulatorStatus] = useState<SimStatus>('stopped')
  const [simulatorEvents, setSimulatorEvents] = useState<string[]>(INITIAL_EVENTS)

  const navigate = (view: MainView) => {
    setActiveView(view)
    setPanel(null)
  }

  return <TooltipProvider>
    <div className={'app-shell' + (sidebarCollapsed ? ' sidebar-collapsed' : '')}>
      <AppSidebar
        activeView={activeView}
        collapsed={sidebarCollapsed}
        onNavigate={navigate}
        onToggleCollapsed={() => setSidebarCollapsed(!sidebarCollapsed)}
      />

      {activeView === 'simulator' ? (
        <SimulatorView
          mode={simulatorMode}
          setMode={setSimulatorMode}
          status={simulatorStatus}
          setStatus={setSimulatorStatus}
          events={simulatorEvents}
          setEvents={setSimulatorEvents}
          openPlayer={() => navigate('player')}
        />
      ) : activeView === 'player' ? (
        <PlayerView />
      ) : activeView === 'components' ? (
        <ComponentCatalogView mode={simulatorMode} status={simulatorStatus} events={simulatorEvents} />
      ) : activeView === 'recorder' ? (
        <RecorderWorkspaceView mode={simulatorMode} status={simulatorStatus} />
      ) : (
        <WorkspaceView
          view={activeView}
          mode={simulatorMode}
          setMode={setSimulatorMode}
          status={simulatorStatus}
          setStatus={setSimulatorStatus}
          events={simulatorEvents}
          setEvents={setSimulatorEvents}
          openPlayer={() => navigate('player')}
        />
      )}
    </div>
  </TooltipProvider>
}

export default App
