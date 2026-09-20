import { Info } from 'lucide-react'
import type { PrimitiveColor, PrimitiveMotion } from './types'
import { primitiveClass } from './types'

export function InfoChip({ color, motion = 'static', children = 'Info chip' }: {
  color: PrimitiveColor
  motion?: PrimitiveMotion
  children?: string
}) {
  return <span className={primitiveClass('primitive-info-chip', color, motion)}>
    <Info size={14} />{children}
  </span>
}
