import { Server } from 'lucide-react'

export function RecorderStatus({ displayName = 'Recorder online' }: { displayName?: string }) {
  return <span className="rep-recorder-status"><Server size={15} /><i className="status-dot" />{displayName}</span>
}
