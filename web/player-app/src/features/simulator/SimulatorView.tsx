import { useState } from 'react'
import { Activity, AlertTriangle, CheckCircle2, ClipboardList, Database, Download, FileText, Pause, Phone, Play, PlayCircle, Radio, Square } from 'lucide-react'
import { ModeSwitch } from './components/ModeSwitch'
import { SummaryCard } from './components/SummaryCard'
import { SidePanel } from './components/SidePanel'
import { RecorderTopology } from './components/RecorderTopology'
import { ActiveServicesTable } from './components/ActiveServicesTable'
import { EventsPanel } from './components/EventsPanel'
import type { SimulatorMode, SimStatus } from './model'
export function SimulatorView({ mode, setMode, status, setStatus, events, setEvents, openPlayer }: {
  mode: SimulatorMode; setMode: (mode: SimulatorMode) => void; status: SimStatus; setStatus: (status: SimStatus) => void; events: string[]; setEvents: (events: string[]) => void; openPlayer: () => void
}) {
  const [expanded, setExpanded] = useState<string[]>(['cwp-a01'])
  const simActive = mode === 'simulation'
  const handleStart = () => { if (!simActive) return; setStatus('running'); setEvents(['Simulação iniciada: TWR - Pico Manhã', ...events]) }
  const handlePause = () => { if (!simActive) return; setStatus('paused'); setEvents(['Simulação pausada pelo operador', ...events]) }
  const handleStop = () => { if (!simActive) return; setStatus('stopped'); setEvents(['Simulação parada pelo operador', ...events]) }
  const handleFault = () => { if (!simActive) return; setEvents(['Falha injetada: RTP packet loss esperado → GAP_START/GAP_END', ...events]) }
  return <main className="sim-main-area">
    <header className="sim-topbar"><div><h1>Simulador de Comunicações</h1><p>{mode === 'capture' ? 'Monitore a captura real feita pelo gravador corrente.' : 'Configure e gere comunicações para teste do gravador.'}</p></div><ModeSwitch mode={mode} onChange={(next) => { setMode(next); setStatus(next === 'capture' ? 'ready' : 'stopped'); setEvents([next === 'capture' ? 'Modo Captura Real ativado' : 'Modo Simulação de Teste ativado', ...events]) }} /><div className="recorder-connected"><i className="status-dot" />Gravador Conectado<span>10.10.0.10</span></div></header>
    <section className="sim-summary-grid"><SummaryCard icon={ClipboardList} title="CWP's" value="4" detail="ativos de 4" /><SummaryCard icon={Radio} title="Rádios" value="8" detail="ativos de 8" tone="green" /><SummaryCard icon={Phone} title="Telefones" value="4" detail="ativos de 4" /><SummaryCard icon={Database} title="Serviços Total" value="16" detail="ativos" tone="green" /><SummaryCard icon={FileText} title="Cenário Atual" value="TWR - Pico Manhã" detail={simActive ? 'em edição' : 'captura corrente'} /><SummaryCard icon={Activity} title="Duração" value={simActive ? '00:30:00' : 'corrente'} detail={status === 'running' ? 'em execução' : 'não iniciado'} tone="orange" /></section>
    <div className="sim-dashboard-grid"><section className="sim-workspace"><div className="sim-sides-layout"><SidePanel side="A" mode={mode} expanded={expanded} setExpanded={setExpanded} /><RecorderTopology mode={mode} status={status} /><SidePanel side="B" mode={mode} expanded={expanded} setExpanded={setExpanded} /></div><ActiveServicesTable mode={mode} /></section><EventsPanel events={events} /></div>
    <footer className="sim-action-bar"><button type="button" className="primary" disabled={!simActive || status === 'running'} onClick={handleStart}><Play size={18} />Iniciar Simulação</button><button type="button" disabled={!simActive || status !== 'running'} onClick={handlePause}><Pause size={18} />Pausar</button><button type="button" disabled={!simActive || status === 'stopped'} onClick={handleStop}><Square size={16} />Parar</button><button type="button" disabled={!simActive} onClick={handleFault}><AlertTriangle size={18} />Injetar Falha</button><button type="button" onClick={openPlayer}><PlayCircle size={18} />Abrir Player</button><button type="button"><Download size={18} />Exportar Relatório</button><span className="sim-system-status"><CheckCircle2 size={18} />{mode === 'capture' ? 'Captura real conectada' : status === 'running' ? 'Simulação gravando no Recorder' : 'Pronto para simular'}</span></footer>
  </main>
}
