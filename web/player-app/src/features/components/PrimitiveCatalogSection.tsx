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
  primitiveId,
  type PrimitiveColor,
  type PrimitiveMotion,
} from '@/primitives'

type PrimitiveSpec = {
  prefix: string
  render: (color: PrimitiveColor, motion: PrimitiveMotion, id: string) => React.ReactNode
}

const SPECS: PrimitiveSpec[] = [
  {
    prefix: 'status_dot',
    render: (color, motion, id) => <StatusDot color={color} motion={motion} label={id} />,
  },
  {
    prefix: 'badge',
    render: (color, motion, id) => <Badge color={color} motion={motion}>{id}</Badge>,
  },
  {
    prefix: 'info_chip',
    render: (color, motion, id) => <InfoChip color={color} motion={motion}>{id}</InfoChip>,
  },
  {
    prefix: 'counter_pill',
    render: (color, motion) => <CounterPill color={color} motion={motion} value={12} label="items" />,
  },
  {
    prefix: 'section_header',
    render: (color, motion) => <SectionHeader color={color} motion={motion} title="Section header" detail="primitive" />,
  },
  {
    prefix: 'mini_metric',
    render: (color, motion) => <MiniMetric color={color} motion={motion} label="Metric" value="42" detail="sample" />,
  },
  {
    prefix: 'tag',
    render: (color, motion, id) => <Tag color={color} motion={motion}>{id}</Tag>,
  },
]

export function PrimitiveCatalogSection({ number }: { number: string }) {
  return <section className="catalog-section">
    <div className="catalog-section-title">
      <div><span>{number}</span><h2>Primitivos visuais</h2></div>
      <p>IDs ubíquos por cor e movimento; sem semântica de domínio.</p>
    </div>

    <div className="primitive-catalog-stack">
      {SPECS.map(spec => <section className="primitive-family" key={spec.prefix}>
        <header><strong>{spec.prefix}</strong><small>green · yellow · red · gray × static · pulse · blink · ping</small></header>
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
    </div>
  </section>
}
