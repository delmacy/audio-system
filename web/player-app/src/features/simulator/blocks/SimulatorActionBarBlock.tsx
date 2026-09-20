import { AlertTriangle, CheckCircle2, Download, Pause, Play, PlayCircle, Square } from 'lucide-react'
import type { SimStatus, SimulatorMode } from '../model'

export function SimulatorActionBarBlock({ mode, status, onStart, onPause, onStop, onFault, openPlayer }: {
  mode: SimulatorMode
  status: SimStatus
  onStart: () => void
  onPause: () => void
  onStop: () => void
  onFault: () => void
  openPlayer: () => void
}) {
  const simActive = mode === 'simulation'

  return <footer className="sim-action-bar">
    <button type="button" className="primary" disabled={!simActive || status === 'running'} onClick={onStart}><Play size={18} />Iniciar Simulação</button>
    <button type="button" disabled={!simActive || status !== 'running'} onClick={onPause}><Pause size={18} />Pausar</button>
    <button type="button" disabled={!simActive || status === 'stopped'} onClick={onStop}><Square size={16} />Parar</button>
    <button type="button" disabled={!simActive} onClick={onFault}><AlertTriangle size={18} />Injetar Falha</button>
    <button type="button" onClick={openPlayer}><PlayCircle size={18} />Abrir Player</button>
    <button type="button"><Download size={18} />Exportar Relatório</button>
    <span className="sim-system-status">
      <CheckCircle2 size={18} />
      {mode === 'capture'
        ? 'Captura real conectada'
        : status === 'running' ? 'Simulação gravando no Recorder' : 'Pronto para simular'}
    </span>
  </footer>
}
