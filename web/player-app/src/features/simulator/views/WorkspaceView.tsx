import { Activity, AlertTriangle, CheckCircle2, Database, FileText, Monitor, Phone, Radio, Server, Wrench } from 'lucide-react'
import { Checkbox } from '@/components/ui/checkbox'
import { ModeSwitch } from '../elements/ModeSwitch'
import { RadioPill } from '@/representations/radio'
import { TelephonePill } from '@/representations/telephone'
import { SIM_CWPS, type CwpConfig, type MainView, type SimulatorMode, type SimStatus } from '../model'
export type WorkspaceViewProps = {
  view: Exclude<MainView, 'simulator' | 'player' | 'components'>
  mode: SimulatorMode
  setMode: (mode: SimulatorMode) => void
  status: SimStatus
  setStatus: (status: SimStatus) => void
  events: string[]
  setEvents: (events: string[]) => void
  openPlayer: () => void
}

function ViewHeader({ title, subtitle, mode, setMode }: { title: string; subtitle: string; mode: SimulatorMode; setMode: (mode: SimulatorMode) => void }) {
  return <header className="workspace-header">
    <div><h1>{title}</h1><p>{subtitle}</p></div>
    <ModeSwitch mode={mode} onChange={setMode} />
    <div className="recorder-connected"><i className="status-dot" />Gravador<span>10.10.0.10</span></div>
  </header>
}

function EnvironmentNote({ mode }: { mode: SimulatorMode }) {
  return <div className="environment-note">
    <CheckCircle2 size={18} />
    <div><strong>{mode === 'capture' ? 'Captura Real' : 'Simulação de Teste'}</strong>
      <span>{mode === 'capture'
        ? 'Mostrando estado do gravador corrente. Esta tela não gera áudio artificial.'
        : 'Mostrando perfis simulados. Áudio gerado aqui deve ser gravado para teste e revisão posterior no Player.'}</span></div>
  </div>
}

function ViewMetric({ icon: Icon, label, value, detail }: { icon: typeof Activity; label: string; value: string; detail: string }) {
  return <article className="view-metric"><Icon size={24} /><span>{label}</span><strong>{value}</strong><small>{detail}</small></article>
}

function ServicesConfigView({ mode }: { mode: SimulatorMode }) {
  const cwpsBySide = ['A', 'B'].map(side => ({ side, cwps: SIM_CWPS.filter(cwp => cwp.side === side) as CwpConfig[] }))
  return <div className="workspace-body">
    <EnvironmentNote mode={mode} />
    <section className="view-grid two">
      {cwpsBySide.map(group => <article className="view-card" key={group.side}>
        <header className="view-card-header"><div><h2>Lado {group.side}</h2><p>CWPs, rádios, telefones e endpoints do ambiente ativo.</p></div><span>{group.cwps.length} CWP</span></header>
        <div className="config-list">
          {group.cwps.map(cwp => {
            const cfg = cwp[mode]
            return <div className="config-item" key={cwp.id}>
              <div className="item-title"><Monitor size={22} /><strong>{cwp.label}</strong><small><i className="status-dot" />Online</small></div>
              <div className="item-fields"><span>Console IP <b>{cfg.consoleIp}</b></span><span>Rádios <b>{cfg.radios}</b></span><span>Telefones <b>{cfg.telephones}</b></span><span>Serviços <b>{cfg.services.length}</b></span></div>
              <div className="item-services">{cfg.services.map(service => service.kind === 'RADIO' ? <RadioPill key={service.id} radio={service} /> : <TelephonePill key={service.id} telephone={service} />)}</div>
              <div className="item-actions"><button type="button"><Wrench size={15} />Editar CWP</button><button type="button"><FileText size={15} />Detalhes</button></div>
            </div>
          })}
        </div>
      </article>)}
    </section>
  </div>
}

function MediaBankView({ mode }: { mode: SimulatorMode }) {
  const clips = [
    ['Rádio / Controller', '21 clips', 'PCMA 8 kHz mono', 'validado'],
    ['Rádio / Pilot', '25 clips', 'PCMA 8 kHz mono', 'validado'],
    ['Telefonia / Ring', '8 tons', 'G.711 A-law', 'pronto'],
    ['Telefonia / Conversations', '12 cenários', 'mono 8 kHz', 'pendente revisão'],
  ]
  return <div className="workspace-body">
    <EnvironmentNote mode={mode} />
    <section className="view-grid three">
      {clips.map(([name, count, format, state]) => <article className="view-card media-card" key={name}>
        <Database size={28} /><h2>{name}</h2><strong>{count}</strong><p>{format}</p><span className="soft-badge">{state}</span>
        <div className="item-actions"><button type="button">Pré-escutar</button><button type="button">Atribuir</button></div>
      </article>)}
    </section>
    <section className="view-card"><header className="view-card-header"><div><h2>Uso no modo ativo</h2><p>O Media Bank só gera tráfego no modo Simulação de Teste. Em Captura Real, ele fica apenas disponível para validação e comparação.</p></div></header></section>
  </div>
}

function ScenariosView({ mode, setMode, setStatus, setEvents, events }: WorkspaceViewProps) {
  const scenarios = [
    ['TWR - Pico Manhã', '30 min', '4 CWP / 8 rádios / 4 telefones', 'pronto'],
    ['APP - Carga Moderada', '45 min', '6 CWP / 10 rádios / 6 telefones', 'rascunho'],
    ['Fault Injection - RTP Loss', '12 min', '2 CWP / perda RTP controlada', 'pronto'],
    ['Stress 30', '60 min', '30 serviços lógicos mono', 'planejado'],
  ]
  return <div className="workspace-body">
    <EnvironmentNote mode={mode} />
    <section className="view-grid two">
      {scenarios.map(([name, duration, scope, state]) => <article className="view-card scenario-card" key={name}>
        <header className="view-card-header"><div><h2>{name}</h2><p>{scope}</p></div><span className="soft-badge">{state}</span></header>
        <div className="scenario-meta"><span>Duração <b>{duration}</b></span><span>Gravador alvo <b>10.10.0.10</b></span></div>
        <div className="item-actions"><button type="button" onClick={() => { setMode('simulation'); setStatus('stopped'); setEvents([`Cenário selecionado: ${name}`, ...events]) }}>Selecionar</button><button type="button">Editar cenário</button></div>
      </article>)}
    </section>
  </div>
}

function ResultsView({ openPlayer }: { openPlayer: () => void }) {
  const runs = [
    ['run-20260920-001', 'TWR - Pico Manhã', 'PASS_WITH_WARNINGS', '12 gaps esperados', '00:30:00'],
    ['run-20260920-002', 'RTP Loss', 'DEGRADED_EXPECTED', 'GAP_START/GAP_END OK', '00:12:00'],
    ['run-20260919-017', 'Stress 10', 'BLOCKED', 'Indexer não executado', '00:15:00'],
  ]
  return <div className="workspace-body"><section className="view-card">
    <header className="view-card-header"><div><h2>Runs e Resultados</h2><p>Histórico de execuções, relatórios e atalhos para abrir a janela gravada no Player.</p></div></header>
    <div className="run-table">{runs.map(run => <div className="run-row" key={run[0]}><strong>{run[0]}</strong><span>{run[1]}</span><b>{run[2]}</b><small>{run[3]}</small><em>{run[4]}</em><button type="button" onClick={openPlayer}>Abrir Player</button></div>)}</div>
  </section></div>
}

function RecorderOpsView({ mode }: { mode: SimulatorMode }) {
  return <div className="workspace-body"><section className="view-grid two">
    <article className="view-card recorder-ops-card"><header className="view-card-header"><div><h2>Gravador Corrente</h2><p>{mode === 'capture' ? 'Fonte da captura real.' : 'Alvo da simulação de teste.'}</p></div><span className="ok-pill">Online</span></header>
      <div className="recorder-detail-grid"><span>IP <b>10.10.0.10</b></span><span>RTSP <b>8554</b></span><span>Storage <b>420 GB / 1 TB</b></span><span>Split <b>60 min</b></span><span>Writer <b>MXF</b></span><span>Codec <b>G.711 A-law</b></span></div></article>
    <article className="view-card recorder-ops-card"><header className="view-card-header"><div><h2>Pipeline</h2><p>Estado dos componentes de captura, escrita e indexação.</p></div></header>
      <div className="health-list big"><span><i />RTSP Ingest OK</span><span><i />RTP Media Engine OK</span><span><i />MXF Writer OK</span><span><i />File Manager OK</span><span><i />SQLite Indexer OK</span><span><i />Event Bus OK</span></div></article>
  </section></div>
}

function FaultInjectionView({ mode, setMode, setStatus, setEvents, events }: WorkspaceViewProps) {
  const faults = ['RTP packet loss', 'RTP duplicate/out-of-order', 'RTSP disconnect', 'SIP abrupt BYE', 'Indexer restart', 'Writer delay']
  return <div className="workspace-body">
    <EnvironmentNote mode={mode} />
    <section className="view-card"><header className="view-card-header"><div><h2>Fault Injection</h2><p>Falhas só podem ser injetadas em Simulação de Teste. Em Captura Real, use apenas monitoramento.</p></div></header>
      <div className="fault-grid">{faults.map(fault => <button type="button" key={fault} disabled={mode !== 'simulation'} onClick={() => { setMode('simulation'); setStatus('running'); setEvents([`Falha programada: ${fault}`, ...events]) }}><AlertTriangle size={18} />{fault}<small>Resultado esperado: evento explícito, nunca perda silenciosa</small></button>)}</div></section>
  </div>
}

function LogsEventsView({ events }: { events: string[] }) {
  return <div className="workspace-body"><section className="view-card"><header className="view-card-header"><div><h2>Logs e Eventos</h2><p>Console operacional filtrável. Eventos P0/P1 devem ser explícitos.</p></div></header>
    <div className="log-console">{events.map((event, index) => <div className="log-row" key={event + index}><span>{new Date(Date.now() - index * 60_000).toLocaleTimeString('pt-BR')}</span><b>{index % 4 === 0 ? 'P0' : index % 3 === 0 ? 'P1' : 'P2'}</b><p>{event}</p></div>)}</div>
  </section></div>
}

function SettingsWorkspaceView({ mode, setMode }: { mode: SimulatorMode; setMode: (mode: SimulatorMode) => void }) {
  return <div className="workspace-body"><EnvironmentNote mode={mode} />
    <section className="view-grid two"><article className="view-card"><header className="view-card-header"><div><h2>Modo Operacional</h2><p>Chave global da aplicação. Não é por CWP.</p></div></header><ModeSwitch mode={mode} onChange={setMode} /></article>
    <article className="view-card"><header className="view-card-header"><div><h2>Regras</h2><p>Produção/captura observa o gravador. Simulação gera tráfego para teste.</p></div></header><ul className="rule-list"><li>CWP direto para Recorder via RTSP/RTP.</li><li>Gateway apenas para SIP/telefonia e rádio físico/legado.</li><li>Live/fixture/silêncio sintético não são evidência.</li></ul></article></section>
  </div>
}

function ExportWorkspaceView({ mode }: { mode: SimulatorMode }) {
  return <div className="workspace-body"><section className="view-card"><header className="view-card-header"><div><h2>Exportação</h2><p>{mode === 'capture' ? 'Exporta evidência de captura real fechada e indexada.' : 'Exporta relatório de teste e, quando houver gravação fechada, abre o Evidence Bundle.'}</p></div></header>
    <div className="export-options"><label><Checkbox checked /> Manifesto</label><label><Checkbox checked /> Source map</label><label><Checkbox checked /> Timeline events</label><label><Checkbox checked /> Hashes SHA-256</label><label><Checkbox /> Áudio WAV do período</label></div>
    <div className="item-actions"><button type="button">Gerar relatório</button><button type="button">Preparar Evidence Bundle</button></div></section></div>
}

export function WorkspaceView(props: WorkspaceViewProps) {
  const titles: Record<WorkspaceViewProps['view'], [string, string]> = {
    services: ['Serviços e CWP', 'Configure consoles, serviços, IPs e vínculos usados pela captura real e pela simulação.'],
    'media-bank': ['Media Bank', 'Organize áudios, tons e conversas usados para gerar tráfego de teste.'],
    scenarios: ['Cenários', 'Monte, selecione e prepare execuções de simulação.'],
    results: ['Runs e Resultados', 'Acompanhe execuções, relatórios e atalhos para revisão no Player.'],
    recorder: ['Gravador', 'Monitore o gravador corrente, pipeline e armazenamento.'],
    faults: ['Fault Injection', 'Programe falhas controladas e resultados esperados.'],
    logs: ['Logs e Eventos', 'Consulte eventos operacionais e auditoria do simulador/gravador.'],
    settings: ['Configurações', 'Ajuste modo operacional e regras globais da aplicação.'],
    export: ['Exportar', 'Gere relatórios, source maps e pacotes evidenciais quando aplicável.'],
  }
  const [title, subtitle] = titles[props.view]
  return <main className="workspace-main">
    <ViewHeader title={title} subtitle={subtitle} mode={props.mode} setMode={props.setMode} />
    <section className="workspace-metrics"><ViewMetric icon={Monitor} label="CWP" value="4" detail="2 lado A / 2 lado B" /><ViewMetric icon={Radio} label="Rádios" value="8" detail="serviços ativos" /><ViewMetric icon={Phone} label="Telefones" value="4" detail="serviços ativos" /><ViewMetric icon={Server} label="Recorder" value="OK" detail="10.10.0.10" /></section>
    {props.view === 'services' && <ServicesConfigView mode={props.mode} />}
    {props.view === 'media-bank' && <MediaBankView mode={props.mode} />}
    {props.view === 'scenarios' && <ScenariosView {...props} />}
    {props.view === 'results' && <ResultsView openPlayer={props.openPlayer} />}
    {props.view === 'recorder' && <RecorderOpsView mode={props.mode} />}
    {props.view === 'faults' && <FaultInjectionView {...props} />}
    {props.view === 'logs' && <LogsEventsView events={props.events} />}
    {props.view === 'settings' && <SettingsWorkspaceView mode={props.mode} setMode={props.setMode} />}
    {props.view === 'export' && <ExportWorkspaceView mode={props.mode} />}
  </main>
}
