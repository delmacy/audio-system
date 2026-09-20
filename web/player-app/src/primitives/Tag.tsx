import { Tag as TagIcon } from 'lucide-react'
import type { PrimitiveColor, PrimitiveMotion } from './types'
import { primitiveClass } from './types'

export function Tag({ color, motion = 'static', children = 'Tag' }: {
  color: PrimitiveColor
  motion?: PrimitiveMotion
  children?: string
}) {
  return <span className={primitiveClass('primitive-tag', color, motion)}><TagIcon size={12} />{children}</span>
}
