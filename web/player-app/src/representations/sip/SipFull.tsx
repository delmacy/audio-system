import { Network } from 'lucide-react'
import { DEMO_SIP_GATEWAY, type SipGatewayConfig } from '@/features/sip/model'

export function SipFull({ gateway = DEMO_SIP_GATEWAY, displayName }: { gateway?: SipGatewayConfig; displayName?: string }) {
  return <article className="rep-sip-full">
    <header>
      <Network size={26} />
      <div><strong>{displayName ?? gateway.name}</strong><small><i className="status-dot" />{gateway.status === 'online' ? 'Online' : 'Offline'}</small></div>
    </header>
    <dl>
      <div><dt>IP</dt><dd>{gateway.ip}</dd></div>
      <div><dt>Porta SIP</dt><dd>{gateway.port}</dd></div>
      <div><dt>Transporte</dt><dd>{gateway.transport}</dd></div>
      <div><dt>Registrar</dt><dd>{gateway.registrar}</dd></div>
      <div><dt>Sessões</dt><dd>{gateway.activeSessions}</dd></div>
      <div><dt>Destino de mídia</dt><dd>{gateway.mediaTarget}</dd></div>
    </dl>
    <p>Responsável pela sinalização SIP e pela integração de telefonia/legado com o fluxo de mídia do sistema.</p>
  </article>
}
