export type MainView = 'simulator' | 'player' | 'services' | 'media-bank' | 'scenarios' | 'results' | 'recorder' | 'faults' | 'logs' | 'settings' | 'export'
export type SimulatorMode = 'capture' | 'simulation'
export type SimStatus = 'ready' | 'running' | 'paused' | 'stopped'

export type ServiceConfig = {
  id: string
  kind: 'RADIO' | 'TEL'
  label: string
  endpoint: string
  status: 'active' | 'idle'
}

export type CwpConfig = {
  id: string
  label: string
  side: 'A' | 'B'
  capture: { consoleIp: string; radios: number; telephones: number; services: ServiceConfig[]; notes: string }
  simulation: { consoleIp: string; radios: number; telephones: number; services: ServiceConfig[]; notes: string }
}

export const SIM_CWPS: CwpConfig[] = [
  { id: 'cwp-a01', label: 'CWP-001', side: 'A',
    capture: { consoleIp: '192.168.1.10', radios: 2, telephones: 1, notes: 'Console real do lado A — torre norte.', services: [
      { id: 'svc-a01-r1', kind: 'RADIO', label: 'TWR 121.500', endpoint: 'rtsp://10.10.0.10:8554/twr-121500', status: 'active' },
      { id: 'svc-a01-r2', kind: 'RADIO', label: 'TWR 118.700', endpoint: 'rtsp://10.10.0.10:8554/twr-118700', status: 'active' },
      { id: 'svc-a01-t1', kind: 'TEL', label: 'TEL-050', endpoint: 'sip:tel-050@10.10.0.20:5060', status: 'active' },
    ]},
    simulation: { consoleIp: '10.20.1.101', radios: 2, telephones: 1, notes: 'Console simulada do lado A para validação de integração.', services: [
      { id: 'sim-a01-r1', kind: 'RADIO', label: 'TWR-SIM 121.500', endpoint: 'rtsp://10.10.0.10:8554/sim-a01-r1', status: 'active' },
      { id: 'sim-a01-r2', kind: 'RADIO', label: 'TWR-SIM 118.700', endpoint: 'rtsp://10.10.0.10:8554/sim-a01-r2', status: 'active' },
      { id: 'sim-a01-t1', kind: 'TEL', label: 'TEL-SIM-050', endpoint: 'sip:sim-a01-t1@10.10.0.20:5060', status: 'active' },
    ]} },
  { id: 'cwp-a02', label: 'CWP-002', side: 'A',
    capture: { consoleIp: '192.168.1.11', radios: 2, telephones: 1, notes: 'Console real do lado A — aproximação.', services: [
      { id: 'svc-a02-r1', kind: 'RADIO', label: 'APP 125.800', endpoint: 'rtsp://10.10.0.10:8554/app-125800', status: 'active' },
      { id: 'svc-a02-r2', kind: 'RADIO', label: 'APP 127.300', endpoint: 'rtsp://10.10.0.10:8554/app-127300', status: 'active' },
      { id: 'svc-a02-t1', kind: 'TEL', label: 'TEL-051', endpoint: 'sip:tel-051@10.10.0.20:5060', status: 'active' },
    ]},
    simulation: { consoleIp: '10.20.1.102', radios: 2, telephones: 1, notes: 'Console simulada do lado A — cenário APP.', services: [
      { id: 'sim-a02-r1', kind: 'RADIO', label: 'APP-SIM 125.800', endpoint: 'rtsp://10.10.0.10:8554/sim-a02-r1', status: 'active' },
      { id: 'sim-a02-r2', kind: 'RADIO', label: 'APP-SIM 127.300', endpoint: 'rtsp://10.10.0.10:8554/sim-a02-r2', status: 'active' },
      { id: 'sim-a02-t1', kind: 'TEL', label: 'TEL-SIM-051', endpoint: 'sip:sim-a02-t1@10.10.0.20:5060', status: 'active' },
    ]} },
  { id: 'cwp-b01', label: 'CWP-B01', side: 'B',
    capture: { consoleIp: '192.168.2.10', radios: 2, telephones: 1, notes: 'Console real do lado B — solo e coordenação.', services: [
      { id: 'svc-b01-r1', kind: 'RADIO', label: 'GND 121.900', endpoint: 'rtsp://10.10.0.10:8554/gnd-121900', status: 'active' },
      { id: 'svc-b01-r2', kind: 'RADIO', label: 'TWR 121.500', endpoint: 'rtsp://10.10.0.10:8554/twr-b-121500', status: 'active' },
      { id: 'svc-b01-t1', kind: 'TEL', label: 'TEL-060', endpoint: 'sip:tel-060@10.10.0.20:5060', status: 'active' },
    ]},
    simulation: { consoleIp: '10.20.2.101', radios: 2, telephones: 1, notes: 'Console simulada do lado B para comunicação cruzada com lado A.', services: [
      { id: 'sim-b01-r1', kind: 'RADIO', label: 'GND-SIM 121.900', endpoint: 'rtsp://10.10.0.10:8554/sim-b01-r1', status: 'active' },
      { id: 'sim-b01-r2', kind: 'RADIO', label: 'TWR-SIM 121.500', endpoint: 'rtsp://10.10.0.10:8554/sim-b01-r2', status: 'active' },
      { id: 'sim-b01-t1', kind: 'TEL', label: 'TEL-SIM-060', endpoint: 'sip:sim-b01-t1@10.10.0.20:5060', status: 'active' },
    ]} },
  { id: 'cwp-b02', label: 'CWP-B02', side: 'B',
    capture: { consoleIp: '192.168.2.11', radios: 2, telephones: 1, notes: 'Console real do lado B — apoio operacional.', services: [
      { id: 'svc-b02-r1', kind: 'RADIO', label: 'APP 125.800', endpoint: 'rtsp://10.10.0.10:8554/app-b-125800', status: 'active' },
      { id: 'svc-b02-r2', kind: 'RADIO', label: 'APP 127.300', endpoint: 'rtsp://10.10.0.10:8554/app-b-127300', status: 'active' },
      { id: 'svc-b02-t1', kind: 'TEL', label: 'TEL-061', endpoint: 'sip:tel-061@10.10.0.20:5060', status: 'active' },
    ]},
    simulation: { consoleIp: '10.20.2.102', radios: 2, telephones: 1, notes: 'Console simulada do lado B — carga complementar.', services: [
      { id: 'sim-b02-r1', kind: 'RADIO', label: 'APP-SIM 125.800', endpoint: 'rtsp://10.10.0.10:8554/sim-b02-r1', status: 'active' },
      { id: 'sim-b02-r2', kind: 'RADIO', label: 'APP-SIM 127.300', endpoint: 'rtsp://10.10.0.10:8554/sim-b02-r2', status: 'active' },
      { id: 'sim-b02-t1', kind: 'TEL', label: 'TEL-SIM-061', endpoint: 'sip:sim-b02-t1@10.10.0.20:5060', status: 'active' },
    ]} },
]

