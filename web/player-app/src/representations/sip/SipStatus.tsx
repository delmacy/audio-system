import { Network } from 'lucide-react'

export function SipStatus({ displayName = 'Gateway SIP online' }: { displayName?: string }) {
  return <span className="rep-sip-status"><Network size={15} /><i className="status-dot" />{displayName}</span>
}
