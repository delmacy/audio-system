import { BLOCK_COLORS, BLOCK_FILLS, VisualBlock } from '@/primitives'

export function BlockPrimitiveCatalogSection({ number }: { number: string }) {
  return <section className="catalog-section">
    <div className="catalog-section-title">
      <div><span>{number}</span><h2>Bloco primitivo</h2></div>
      <p>Container neutro: cor de borda × cor interna × static/pulse. Sem composição funcional.</p>
    </div>

    <div className="primitive-family">
      <header><strong>block</strong><small>blue · gray · red · green · yellow · purple × fill white/cor × static/pulse</small></header>
      <div className="block-primitive-grid">
        {BLOCK_COLORS.flatMap(borderColor => BLOCK_FILLS.flatMap(fillColor => (['static','pulse'] as const).map(motion => {
          const id = `block_${borderColor}_fill_${fillColor}${motion === 'pulse' ? '_pulse' : ''}`
          return <article className="primitive-specimen block-specimen" key={id} id={id}>
            <div className="primitive-specimen-preview">
              <VisualBlock borderColor={borderColor} fillColor={fillColor} motion={motion} label={id} />
            </div>
            <code>{id}</code>
          </article>
        })))}
      </div>
    </div>
  </section>
}
