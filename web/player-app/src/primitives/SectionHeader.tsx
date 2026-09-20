import type { PrimitiveColor, PrimitiveMotion } from './types'
import { primitiveClass } from './types'

export function SectionHeader({ color, motion = 'static', title = 'Section header', detail = 'subsection' }: {
  color: PrimitiveColor
  motion?: PrimitiveMotion
  title?: string
  detail?: string
}) {
  return <div className={primitiveClass('primitive-section-header', color, motion)}>
    <i />
    <div><strong>{title}</strong><small>{detail}</small></div>
  </div>
}
