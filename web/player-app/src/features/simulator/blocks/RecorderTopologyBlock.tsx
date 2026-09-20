import { RecorderFull } from '@/representations/recorder'
import type { SimStatus, SimulatorMode } from '../model'

export function RecorderTopologyBlock({ mode, status }: { mode: SimulatorMode; status: SimStatus }) {
  return <RecorderFull mode={mode} status={status} />
}
