export type RecorderConfig = {
  name: string
  ip: string
  rtspPort: number
  sipGatewayIp: string
  sipPort: number
  storageUsedGb: number
  storageTotalGb: number
  splitMinutes: number
  writer: string
  codec: string
  streams: number
}

export const DEMO_RECORDER: RecorderConfig = {
  name: 'Recorder 01',
  ip: '10.10.0.10',
  rtspPort: 8554,
  sipGatewayIp: '10.10.0.20',
  sipPort: 5060,
  storageUsedGb: 420,
  storageTotalGb: 1000,
  splitMinutes: 60,
  writer: 'MXF',
  codec: 'G.711 A-law',
  streams: 16,
}
