import { useState } from 'react'
import { TooltipProvider } from '@/components/ui/tooltip'
import { AppSidebar } from '@/app/AppSidebar'
import { ComponentCatalogView } from '@/features/components/ComponentCatalogView'
import { ServiceRegistryView } from '@/features/services/ServiceRegistryView'
import type { MainView } from '@/features/simulator/model'
import './App.css'

const CATALOG_EVENTS = [
  'Gravador pronto em 10.10.0.10',
  'Gateway SIP online em 10.10.0.20',
  'CWP-A01 conectado',
]

function Placeholder({ title }: { title: string }) {
  return <main className="product-placeholder">
    <span>Audio System</span>
    <h1>{title}</h1>
    <p>Esta área será composta nas próximas etapas.</p>
  </main>
}

function App() {
  const [activeView, setActiveView] = useState<MainView>('services')
  const [collapsed, setCollapsed] = useState(false)

  let content: React.ReactNode
  if (activeView === 'services') content = <ServiceRegistryView />
  else if (activeView === 'components') content = <ComponentCatalogView mode="simulation" status="stopped" events={CATALOG_EVENTS} />
  else if (activeView === 'simulator') content = <Placeholder title="Simulador" />
  else if (activeView === 'player') content = <Placeholder title="Player" />
  else if (activeView === 'recorder') content = <Placeholder title="Gravador" />
  else content = <Placeholder title="Configurações" />

  return <TooltipProvider>
    <div className={'product-shell' + (collapsed ? ' sidebar-collapsed' : '')}>
      <AppSidebar
        activeView={activeView}
        collapsed={collapsed}
        onNavigate={setActiveView}
        onToggleCollapsed={() => setCollapsed(value => !value)}
      />
      <div className="product-content">{content}</div>
    </div>
  </TooltipProvider>
}

export default App
