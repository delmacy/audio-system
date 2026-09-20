import { ModeSwitch } from '../elements/ModeSwitch'
import type { SimStatus, SimulatorMode } from '../model'

export function SimulatorHeaderBlock({ mode, setMode, setStatus, events, setEvents }: {
  mode: SimulatorMode
  setMode: (mode: SimulatorMode) => void
  setStatus: (status: SimStatus) => void
  events: string[]
  setEvents: (events: string[]) => void
}) {
  return <header className="sim-topbar">
    <div>
      <h1>Simulador de Comunicações</h1>
      <p>{mode === 'capture'
        ? 'Monitore a captura real feita pelo gravador corrente.'
        : 'Configure e gere comunicações para teste do gravador.'}</p>
    </div>

    <ModeSwitch mode={mode} onChange={(next) => {
      setMode(next)
      setStatus(next === 'capture' ? 'ready' : 'stopped')
      setEvents([next === 'capture' ? 'Modo Captura Real ativado' : 'Modo Simulação de Teste ativado', ...events])
    }} />

    <div className="recorder-connected">
      <i className="status-dot" />Gravador Conectado<span>10.10.0.10</span>
    </div>
  </header>
}
