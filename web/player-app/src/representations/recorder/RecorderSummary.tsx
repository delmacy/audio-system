import { Server } from 'lucide-react'
import type { SimStatus } from '@/features/simulator/model'

export function RecorderSummary({ status, onClick, displayName = 'Recorder 01' }: { status: SimStatus; onClick?: () => void; displayName?: string }) {
  return <button type="button" className="rep-recorder-summary" onClick={onClick}>
    <Server size={19} />
    <strong>{displayName}</strong>
    <span>10.10.0.10</span>
    <span>RTSP 8554</span>
    <small><i className="status-dot" />{status === 'running' ? 'Gravando' : 'Online'}</small>
  </button>
}
