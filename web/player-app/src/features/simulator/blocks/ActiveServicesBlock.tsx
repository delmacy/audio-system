import { Database, Phone, Radio } from 'lucide-react'
import { ActiveServicesList, type ActiveServiceRow } from '../lists/ActiveServicesList'
import { SIM_CWPS, type SimulatorMode } from '../model'

export function ActiveServicesBlock({ mode }: { mode: SimulatorMode }) {
  const services: ActiveServiceRow[] = SIM_CWPS.flatMap(cwp =>
    cwp[mode].services.map(service => ({ ...service, cwp: cwp.label, side: cwp.side })),
  )
  const radios = services.filter(service => service.kind === 'RADIO').length
  const tels = services.filter(service => service.kind === 'TEL').length

  return <section className="active-services-card">
    <header>
      <div>
        <Database size={31} />
        <div>
          <h2>Serviços Ativos</h2>
          <p>{mode === 'capture'
            ? 'Serviços reais detectados/cadastrados no gravador corrente.'
            : 'Serviços simulados que serão gerados para teste e gravados.'}</p>
        </div>
      </div>
      <div className="service-counters">
        <span><Radio size={15} />Rádios {radios}</span>
        <span><Phone size={15} />Telefones {tels}</span>
        <span>Total {services.length}</span>
      </div>
    </header>

    <ActiveServicesList services={services} />
  </section>
}
