import { Server } from 'lucide-react'

export function RecorderStatus() {
  return <span className="rep-recorder-status"><Server size={15} /><i className="status-dot" />Recorder online</span>
}
