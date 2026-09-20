import type { SimulatorMode } from '../model'

export function ModeSwitch({ mode, onChange }: { mode: SimulatorMode; onChange: (mode: SimulatorMode) => void }) {
  return <div className="mode-switch" role="group" aria-label="Modo operacional">
    <span>Modo operacional</span>
    <button type="button" className={mode === 'capture' ? 'active' : ''} onClick={() => onChange('capture')}>Captura Real</button>
    <button type="button" className={mode === 'simulation' ? 'active' : ''} onClick={() => onChange('simulation')}>Simulação de Teste</button>
  </div>
}
