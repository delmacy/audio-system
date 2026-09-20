import { Server } from 'lucide-react'
import type { SimStatus } from '@/features/simulator/model'

export function RecorderSummary({ status, onClick }: { status: SimStatus; onClick?: () => void }) {
  return <button type="button" className="rep-recorder-summary" onClick={onClick}>
    <Server size={19} />
    <strong>Recorder 01</strong>
    <span>10.10.0.10</span>
    <span>RTSP 8554</span>
    <small><i className="status-dot" />{status === 'running' ? 'Gravando' : 'Online'}</small>
  </button>
}
