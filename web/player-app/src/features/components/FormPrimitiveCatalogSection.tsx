import { Field, FORM_PRIMITIVE_COLORS, TextareaField } from '@/primitives'

export function FormPrimitiveCatalogSection({ number }: { number: string }) {
  return <section className="catalog-section">
    <div className="catalog-section-title">
      <div><span>{number}</span><h2>Fields e Textarea</h2></div>
      <p>Primitivos de formulário prontos para composições futuras.</p>
    </div>

    <div className="primitive-family">
      <header><strong>field</strong><small>blue · gray · red · green · purple × static · pulse + disabled</small></header>
      <div className="form-primitive-grid">
        {FORM_PRIMITIVE_COLORS.flatMap(color => (['static', 'pulse'] as const).map(motion => {
          const id = `field_${color}${motion === 'pulse' ? '_pulse' : ''}`
          return <article className="primitive-specimen form-specimen" key={id} id={id}>
            <div className="primitive-specimen-preview">
              <Field color={color} motion={motion} label={id} helper="helper text" placeholder="valor..." />
            </div>
            <code>{id}</code>
          </article>
        }))}
        {FORM_PRIMITIVE_COLORS.map(color => {
          const id = `field_${color}_disabled`
          return <article className="primitive-specimen form-specimen" key={id} id={id}>
            <div className="primitive-specimen-preview">
              <Field color={color} label={id} disabled defaultValue="disabled" />
            </div>
            <code>{id}</code>
          </article>
        })}
      </div>
    </div>

    <div className="primitive-family">
      <header><strong>textarea</strong><small>blue · gray · red · green · purple × static · pulse + disabled</small></header>
      <div className="form-primitive-grid">
        {FORM_PRIMITIVE_COLORS.flatMap(color => (['static', 'pulse'] as const).map(motion => {
          const id = `textarea_${color}${motion === 'pulse' ? '_pulse' : ''}`
          return <article className="primitive-specimen form-specimen" key={id} id={id}>
            <div className="primitive-specimen-preview">
              <TextareaField color={color} motion={motion} label={id} helper="helper text" placeholder="conteúdo..." rows={3} />
            </div>
            <code>{id}</code>
          </article>
        }))}
        {FORM_PRIMITIVE_COLORS.map(color => {
          const id = `textarea_${color}_disabled`
          return <article className="primitive-specimen form-specimen" key={id} id={id}>
            <div className="primitive-specimen-preview">
              <TextareaField color={color} label={id} disabled defaultValue="disabled" rows={3} />
            </div>
            <code>{id}</code>
          </article>
        })}
      </div>
    </div>
  </section>
}
