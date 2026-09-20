import type { PrimitiveColor, PrimitiveMotion } from './types'
import { primitiveClass } from './types'

export function Badge({ color, motion = 'static', children = 'Badge' }: {
  color: PrimitiveColor
  motion?: PrimitiveMotion
  children?: string
}) {
  return <span className={primitiveClass('primitive-badge', color, motion)}>{children}</span>
}
