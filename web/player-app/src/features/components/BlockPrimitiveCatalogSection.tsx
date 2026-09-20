import { BLOCK_COLORS, BLOCK_MOTIONS, VisualBlock } from '@/primitives'

function blockId(color: string, motion: 'static' | 'pulse' | 'fill-pulse') {
  if (motion === 'static') return `block_${color}`
  if (motion === 'pulse') return `block_${color}_pulse`
  return `block_${color}_fill_pulse`
}

export function BlockPrimitiveCatalogSection({ number }: { number: string }) {
  return <section className="catalog-section">
    <div className="catalog-section-title">
      <div><span>{number}</span><h2>Bloco primitivo</h2></div>
      <p>Uma única cor para borda e preenchimento, com pulso externo ou pulso interno.</p>
    </div>

    <div className="primitive-family">
      <header>
        <strong>block</strong>
        <small>white · black · gray · blue · green · yellow · red · purple × static · pulse · fill_pulse</small>
      </header>

      <div className="block-primitive-grid">
        {BLOCK_COLORS.flatMap(color => BLOCK_MOTIONS.map(motion => {
          const id = blockId(color, motion)
          return <article className="primitive-specimen block-specimen" key={id} id={id}>
            <div className="primitive-specimen-preview">
              <VisualBlock color={color} motion={motion} label={id} />
            </div>
            <code>{id}</code>
          </article>
        }))}
      </div>
    </div>
  </section>
}
