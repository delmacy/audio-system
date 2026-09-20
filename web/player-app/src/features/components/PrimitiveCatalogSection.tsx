import { useState } from 'react'
import {
  Badge,
  CounterPill,
  InfoChip,
  MiniMetric,
  PRIMITIVE_COLORS,
  PRIMITIVE_MOTIONS,
  SectionHeader,
  StatusDot,
  Tag,
  PrimitiveButton,
  primitiveId,
  type PrimitiveColor,
  type PrimitiveMotion,
  type PrimitiveButtonColor,
  type PrimitiveButtonVariant,
  type PrimitiveButtonSize,
  type PrimitiveButtonIcon,
  DataSourceStatus,
  DataProbe,
} from '@/primitives'

type PrimitiveSpec = {
  prefix: string
  group: 'status' | 'labels' | 'metrics'
  render: (color: PrimitiveColor, motion: PrimitiveMotion, id: string) => React.ReactNode
}

const SPECS: PrimitiveSpec[] = [
  { prefix: 'status_dot', group: 'status', render: (color, motion, id) => <StatusDot color={color} motion={motion} label={id} /> },
  { prefix: 'badge', group: 'labels', render: (color, motion, id) => <Badge color={color} motion={motion}>{id}</Badge> },
  { prefix: 'info_chip', group: 'labels', render: (color, motion, id) => <InfoChip color={color} motion={motion}>{id}</InfoChip> },
  { prefix: 'counter_pill', group: 'labels', render: (color, motion) => <CounterPill color={color} motion={motion} value={12} label="items" /> },
  { prefix: 'tag', group: 'labels', render: (color, motion, id) => <Tag color={color} motion={motion}>{id}</Tag> },
  { prefix: 'section_header', group: 'metrics', render: (color, motion) => <SectionHeader color={color} motion={motion} title="Section header" detail="primitive" /> },
  { prefix: 'mini_metric', group: 'metrics', render: (color, motion) => <MiniMetric color={color} motion={motion} label="Metric" value="42" detail="sample" /> },
]

const BUTTON_COLORS: PrimitiveButtonColor[] = ['blue', 'gray', 'red', 'green', 'purple']
const BUTTON_VARIANTS: PrimitiveButtonVariant[] = ['solid', 'outline', 'ghost']
const BUTTON_SIZES: PrimitiveButtonSize[] = ['sm', 'md', 'lg']
const BUTTON_ICONS: PrimitiveButtonIcon[] = ['plus', 'x', 'play', 'pause', 'square', 'download', 'alert_triangle']

type PrimitiveTab = 'buttons' | 'status' | 'labels' | 'metrics' | 'data'

function ButtonPrimitiveCatalog() {
  return <section className="primitive-family">
    <header><strong>button</strong><small>cor × tratamento × tamanho + pulse + disabled + ícones nomeados</small></header>

    <h3 className="primitive-subtitle">Botões de texto</h3>
    <div className="primitive-button-grid">
      {BUTTON_COLORS.flatMap(color => BUTTON_VARIANTS.flatMap(variant => BUTTON_SIZES.map(size => {
        const id = `button_${color}_${variant}_${size}`
        return <article className="primitive-specimen" key={id} id={id}>
          <div className="primitive-specimen-preview"><PrimitiveButton color={color} variant={variant} size={size}>{id}</PrimitiveButton></div>
          <code>{id}</code>
        </article>
      })))}
    </div>

    <h3 className="primitive-subtitle">Botões pulsantes</h3>
    <div className="primitive-button-grid">
      {BUTTON_COLORS.flatMap(color => BUTTON_VARIANTS.map(variant => {
        const id = `button_${color}_${variant}_md_pulse`
        return <article className="primitive-specimen" key={id} id={id}>
          <div className="primitive-specimen-preview"><PrimitiveButton color={color} variant={variant} motion="pulse">{id}</PrimitiveButton></div>
          <code>{id}</code>
        </article>
      }))}
    </div>

    <h3 className="primitive-subtitle">Estados disabled</h3>
    <div className="primitive-button-grid">
      {BUTTON_COLORS.map(color => {
        const id = `button_${color}_solid_disabled`
        return <article className="primitive-specimen" key={id} id={id}>
          <div className="primitive-specimen-preview"><PrimitiveButton color={color} variant="solid" disabled>{id}</PrimitiveButton></div>
          <code>{id}</code>
        </article>
      })}
    </div>

    <h3 className="primitive-subtitle">Botões somente ícone</h3>
    <div className="primitive-button-grid">
      {BUTTON_COLORS.flatMap(color => BUTTON_ICONS.map(icon => {
        const id = `button_${color}_ghost_icon_${icon}`
        return <article className="primitive-specimen" key={id} id={id}>
          <div className="primitive-specimen-preview"><PrimitiveButton color={color} variant="ghost" icon={icon} iconOnly ariaLabel={id} /></div>
          <code>{id}</code>
        </article>
      }))}
    </div>
  </section>
}

function PrimitiveFamilies({ group }: { group: PrimitiveSpec['group'] }) {
  return <>
    {SPECS.filter(spec => spec.group === group).map(spec => <section className="primitive-family" key={spec.prefix}>
      <header><strong>{spec.prefix}</strong><small>green · yellow · red · gray · purple × static · pulse · blink · ping</small></header>
      <div className="primitive-variant-grid">
        {PRIMITIVE_COLORS.flatMap(color => PRIMITIVE_MOTIONS.map(motion => {
          const id = primitiveId(spec.prefix, color, motion)
          return <article className="primitive-specimen" key={id} id={id}>
            <div className="primitive-specimen-preview">{spec.render(color, motion, id)}</div>
            <code>{id}</code>
          </article>
        }))}
      </div>
    </section>)}
  </>
}

export function PrimitiveCatalogSection({ number }: { number: string }) {
  const [tab, setTab] = useState<PrimitiveTab>('buttons')

  return <section className="catalog-section">
    <div className="catalog-section-title">
      <div><span>{number}</span><h2>Primitivos visuais</h2></div>
      <p>IDs ubíquos baseados em aparência; sem semântica de domínio.</p>
    </div>

    <nav className="primitive-tabs" aria-label="Tipos de primitivos visuais">
      <button type="button" className={tab === 'buttons' ? 'active' : ''} onClick={() => setTab('buttons')}>Botões</button>
      <button type="button" className={tab === 'status' ? 'active' : ''} onClick={() => setTab('status')}>Status</button>
      <button type="button" className={tab === 'labels' ? 'active' : ''} onClick={() => setTab('labels')}>Badges · Tags · Chips</button>
      <button type="button" className={tab === 'metrics' ? 'active' : ''} onClick={() => setTab('metrics')}>Métricas · Headers</button>
      <button type="button" className={tab === 'data' ? 'active' : ''} onClick={() => setTab('data')}>Data</button>
    </nav>

    <div className="primitive-catalog-stack">
      {tab === 'buttons' && <ButtonPrimitiveCatalog />}
      {tab === 'status' && <PrimitiveFamilies group="status" />}
      {tab === 'labels' && <PrimitiveFamilies group="labels" />}
      {tab === 'metrics' && <PrimitiveFamilies group="metrics" />}
      {tab === 'data' && <section className="primitive-family">
        <header><strong>data diagnostics</strong><small>estado da fonte e contagem RAW → DTO → UI</small></header>
        <div className="primitive-variant-grid">
          {(['connected','loading','empty','stale','error'] as const).map(state => <article className="primitive-specimen" id={`data_source_status_${state}`} key={state}>
            <div className="primitive-specimen-preview"><DataSourceStatus state={state} source="timeline-api" detail={state} updatedAt="16:42:13" /></div>
            <code>{`data_source_status_${state}`}</code>
          </article>)}
          <article className="primitive-specimen" id="data_probe">
            <div className="primitive-specimen-preview"><DataProbe rawCount={27} dtoCount={27} renderedCount={27} discardedCount={0} /></div>
            <code>data_probe</code>
          </article>
        </div>
      </section>}
    </div>
  </section>
}
