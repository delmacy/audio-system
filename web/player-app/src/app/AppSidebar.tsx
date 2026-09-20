import {
  Activity, AlertTriangle, CalendarDays, ChevronLeft, ChevronRight, ClipboardList,
  Database, Download, FileText, Home, LayoutGrid, PlayCircle, Server, Settings2, SlidersHorizontal,
} from 'lucide-react'
import type { MainView } from '@/features/simulator/model'

const NAV = [
  { label: 'Simulador', icon: Home, view: 'simulator' as MainView },
  { label: 'Player', icon: PlayCircle, view: 'player' as MainView },
  { label: 'Componentes', icon: LayoutGrid, view: 'components' as MainView },
  { label: 'Serviços', icon: SlidersHorizontal, view: 'services' as MainView },
  { label: 'Media Bank', icon: Database, view: 'media-bank' as MainView },
  { label: 'Cenários', icon: ClipboardList, view: 'scenarios' as MainView },
  { label: 'Resultados', icon: FileText, view: 'results' as MainView },
  { label: 'Gravador', icon: Server, view: 'recorder' as MainView },
  { label: 'Falhas', icon: AlertTriangle, view: 'faults' as MainView },
  { label: 'Logs e Eventos', icon: CalendarDays, view: 'logs' as MainView },
  { label: 'Exportar', icon: Download, view: 'export' as MainView },
  { label: 'Configurações', icon: Settings2, view: 'settings' as MainView },
]

type Props = {
  activeView: MainView
  collapsed: boolean
  onNavigate: (view: MainView) => void
  onToggleCollapsed: () => void
}

export function AppSidebar({ activeView, collapsed, onNavigate, onToggleCollapsed }: Props) {
  return <aside className="app-sidebar" aria-label="Menu principal">
    <div className="brand"><Activity size={31} strokeWidth={2.4} /><div><strong>CommSuite</strong><span>Recorder & Simulator</span></div></div>
    <nav className="nav-list" aria-label="Navegação">
      {NAV.map(item => <button key={item.label} type="button" className={'nav-item' + (activeView === item.view ? ' active' : '')}
        aria-label={item.label} title={item.label} onClick={() => onNavigate(item.view)}>
        <item.icon size={20} strokeWidth={1.8} /><span>{item.label}</span>
      </button>)}
    </nav>
    <button className="collapse-button" type="button" onClick={onToggleCollapsed}
      aria-label={collapsed ? 'Expandir menu' : 'Recolher menu'}>
      {collapsed ? <ChevronRight size={18} /> : <ChevronLeft size={18} />}
      <span>{collapsed ? 'Expandir' : 'Recolher'}</span>
    </button>
  </aside>
}
