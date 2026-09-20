import type { PrimitiveColor, PrimitiveMotion } from './types'
import { primitiveClass } from './types'

export function StatusDot({ color, motion = 'static', size = 'md', label }: {
  color: PrimitiveColor
  motion?: PrimitiveMotion
  size?: 'sm' | 'md' | 'lg'
  label?: string
}) {
  return <span className="primitive-status-wrap">
    <i className={`${primitiveClass('primitive-status-dot', color, motion)} primitive-size-${size}`} />
    {label && <span>{label}</span>}
  </span>
}
