import { RecorderFull } from '@/representations/recorder'
import { SipFull } from '@/representations/sip'
import type { SimStatus, SimulatorMode } from '../model'

export function RecorderTopologyBlock({ mode, status }: { mode: SimulatorMode; status: SimStatus }) {
  return <div className="topology-core-stack">
    <RecorderFull mode={mode} status={status} />
    <div className="flow-line"><span>integração SIP → mídia</span></div>
    <SipFull />
  </div>
}
