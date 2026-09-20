import { useState } from 'react'
import { EventsBlock } from '../blocks/EventsBlock'
import { SimulatorActionBarBlock } from '../blocks/SimulatorActionBarBlock'
import { SimulatorHeaderBlock } from '../blocks/SimulatorHeaderBlock'
import { SimulatorWorkspaceBlock } from '../blocks/SimulatorWorkspaceBlock'
import { SummaryBlock } from '../blocks/SummaryBlock'
import type { SimulatorMode, SimStatus } from '../model'

export function SimulatorView({ mode, setMode, status, setStatus, events, setEvents, openPlayer }: {
  mode: SimulatorMode
  setMode: (mode: SimulatorMode) => void
  status: SimStatus
  setStatus: (status: SimStatus) => void
  events: string[]
  setEvents: (events: string[]) => void
  openPlayer: () => void
}) {
  const [expanded, setExpanded] = useState<string[]>(['cwp-a01'])
  const simActive = mode === 'simulation'

  const handleStart = () => {
    if (!simActive) return
    setStatus('running')
    setEvents(['Simulação iniciada: TWR - Pico Manhã', ...events])
  }

  const handlePause = () => {
    if (!simActive) return
    setStatus('paused')
    setEvents(['Simulação pausada pelo operador', ...events])
  }

  const handleStop = () => {
    if (!simActive) return
    setStatus('stopped')
    setEvents(['Simulação parada pelo operador', ...events])
  }

  const handleFault = () => {
    if (!simActive) return
    setEvents(['Falha injetada: RTP packet loss esperado → GAP_START/GAP_END', ...events])
  }

  return <main className="sim-main-area">
    <SimulatorHeaderBlock
      mode={mode}
      setMode={setMode}
      setStatus={setStatus}
      events={events}
      setEvents={setEvents}
    />

    <SummaryBlock simActive={simActive} status={status} />

    <div className="sim-dashboard-grid">
      <SimulatorWorkspaceBlock
        mode={mode}
        status={status}
        expanded={expanded}
        setExpanded={setExpanded}
      />
      <EventsBlock events={events} />
    </div>

    <SimulatorActionBarBlock
      mode={mode}
      status={status}
      onStart={handleStart}
      onPause={handlePause}
      onStop={handleStop}
      onFault={handleFault}
      openPlayer={openPlayer}
    />
  </main>
}
