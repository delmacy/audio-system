export type SipGatewayConfig = {
  name: string
  ip: string
  port: number
  transport: 'UDP' | 'TCP' | 'TLS'
  registrar: string
  mediaTarget: string
  activeSessions: number
  status: 'online' | 'offline'
}

export const DEMO_SIP_GATEWAY: SipGatewayConfig = {
  name: 'Gateway SIP 01',
  ip: '10.10.0.20',
  port: 5060,
  transport: 'UDP',
  registrar: '10.10.0.20',
  mediaTarget: 'rtsp://10.10.0.10:8554',
  activeSessions: 4,
  status: 'online',
}
