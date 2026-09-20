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

const BUTTON_COLORS: PrimitiveButtonColor[] = ['blue', 'gray', 'red', 'green']
const BUTTON_VARIANTS: PrimitiveButtonVariant[] = ['solid', 'outline', 'ghost']
const BUTTON_SIZES: PrimitiveButtonSize[] = ['sm', 'md', 'lg']

function ButtonPrimitiveCatalog() {
  return <section className="primitive-family">
    <header><strong>button</strong><small>blue · gray · red · green × solid · outline · ghost × sm · md · lg + disabled + icon</small></header>
    <div className="primitive-button-grid">
      {BUTTON_COLORS.flatMap(color => BUTTON_VARIANTS.flatMap(variant => BUTTON_SIZES.map(size => {
        const id = `button_${color}_${variant}_${size}`
        return <article className="primitive-specimen" key={id} id={id}>
          <div className="primitive-specimen-preview"><PrimitiveButton color={color} variant={variant} size={size}>{id}</PrimitiveButton></div>
          <code>{id}</code>
        </article>
      })))}
      {BUTTON_COLORS.flatMap(color => {
        const disabledId = `button_${color}_solid_disabled`
        const iconId = `button_${color}_ghost_icon`
        return [
          <article className="primitive-specimen" key={disabledId} id={disabledId}>
            <div className="primitive-specimen-preview"><PrimitiveButton color={color} variant="solid" disabled>{disabledId}</PrimitiveButton></div>
            <code>{disabledId}</code>
          </article>,
          <article className="primitive-specimen" key={iconId} id={iconId}>
            <div className="primitive-specimen-preview"><PrimitiveButton color={color} variant="ghost" iconOnly ariaLabel={iconId} /></div>
            <code>{iconId}</code>
          </article>
        ]
      })}
    </div>
  </section>
}

export function PrimitiveCatalogSection({ number }: { number: string }) {
  return <section className="catalog-section">
    <div className="catalog-section-title">
      <div><span>{number}</span><h2>Primitivos visuais</h2></div>
      <p>IDs ubíquos por cor e movimento; sem semântica de domínio.</p>
    </div>

    <div className="primitive-catalog-stack">
      <ButtonPrimitiveCatalog />
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
