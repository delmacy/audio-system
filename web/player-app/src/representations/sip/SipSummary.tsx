import { Network } from 'lucide-react'
import { DEMO_SIP_GATEWAY } from '@/features/sip/model'

export function SipSummary({ displayName = 'Gateway SIP' }: { displayName?: string }) {
  const gateway = DEMO_SIP_GATEWAY
  return <div className="rep-sip-summary">
    <Network size={19} />
    <strong>{displayName}</strong>
    <span>{gateway.ip}</span>
    <span>SIP {gateway.port}/{gateway.transport}</span>
    <small><i className="status-dot" />{gateway.activeSessions} sessões</small>
  </div>
}
