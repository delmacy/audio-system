import type { PrimitiveColor, PrimitiveMotion } from './types'
import { primitiveClass } from './types'

export function CounterPill({ color, motion = 'static', value = 12, label = 'items' }: {
  color: PrimitiveColor
  motion?: PrimitiveMotion
  value?: number
  label?: string
}) {
  return <span className={primitiveClass('primitive-counter-pill', color, motion)}>
    <strong>{value}</strong><span>{label}</span>
  </span>
}
