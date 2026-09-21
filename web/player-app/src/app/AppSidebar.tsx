import {
  Activity, ChevronLeft, ChevronRight, LayoutGrid, PlayCircle, Server, Settings2, SlidersHorizontal,
} from 'lucide-react'
import type { MainView } from '@/features/simulator/model'

const NAV = [
  { label: 'Serviços & CWP', icon: SlidersHorizontal, view: 'services' as MainView },
  { label: 'Simulador', icon: Activity, view: 'simulator' as MainView },
  { label: 'Player', icon: PlayCircle, view: 'player' as MainView },
  { label: 'Gravador', icon: Server, view: 'recorder' as MainView },
  { label: 'Componentes', icon: LayoutGrid, view: 'components' as MainView },
  { label: 'Configurações', icon: Settings2, view: 'settings' as MainView },
]

type Props = {
  activeView: MainView
  collapsed: boolean
  onNavigate: (view: MainView) => void
  onToggleCollapsed: () => void
}

export function AppSidebar({ activeView, collapsed, onNavigate, onToggleCollapsed }: Props) {
  return <aside className={'product-sidebar' + (collapsed ? ' collapsed' : '')} aria-label="Menu principal">
    <div className="product-brand">
      <Activity size={28} strokeWidth={2.2} />
      {!collapsed && <div><strong>Audio System</strong><span>Recorder & Simulator</span></div>}
    </div>
    <nav className="product-nav" aria-label="Navegação">
      {NAV.map(item => <button key={item.label} type="button"
        className={'product-nav-item' + (activeView === item.view ? ' active' : '')}
        aria-label={item.label} title={item.label} onClick={() => onNavigate(item.view)}>
        <item.icon size={19} strokeWidth={1.9} />
        {!collapsed && <span>{item.label}</span>}
      </button>)}
    </nav>
    <button className="product-sidebar-collapse" type="button" onClick={onToggleCollapsed}
      aria-label={collapsed ? 'Expandir menu' : 'Recolher menu'}>
      {collapsed ? <ChevronRight size={17} /> : <ChevronLeft size={17} />}
      {!collapsed && <span>Recolher</span>}
    </button>
  </aside>
}
