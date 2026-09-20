import { Database, Phone, Radio } from 'lucide-react'
import { SIM_CWPS, type SimulatorMode } from '../model'
export function ActiveServicesTable({ mode }: { mode: SimulatorMode }) {
  const services = SIM_CWPS.flatMap(cwp => cwp[mode].services.map(service => ({ ...service, cwp: cwp.label, side: cwp.side })))
  const radios = services.filter(service => service.kind === 'RADIO').length
  const tels = services.filter(service => service.kind === 'TEL').length
  return <section className="active-services-card">
    <header><div><Database size={31} /><div><h2>Serviços Ativos</h2><p>{mode === 'capture' ? 'Serviços reais detectados/cadastrados no gravador corrente.' : 'Serviços simulados que serão gerados para teste e gravados.'}</p></div></div>
      <div className="service-counters"><span><Radio size={15} />Rádios {radios}</span><span><Phone size={15} />Telefones {tels}</span><span>Total {services.length}</span></div></header>
    <div className="services-table">
      {services.map(service => <div key={service.id} className="service-row">
        <span className={'svc-kind ' + service.kind.toLowerCase()}>{service.kind}</span><strong>{service.label}</strong><span>{service.cwp}</span><span>Lado {service.side}</span><small><i className="status-dot" />Ativo</small>
      </div>)}
    </div>
  </section>
}

