import { Activity } from 'lucide-react'
import type { PrimitiveColor, PrimitiveMotion } from './types'
import { primitiveClass } from './types'

export function MiniMetric({ color, motion = 'static', label = 'Metric', value = '42', detail = 'sample' }: {
  color: PrimitiveColor
  motion?: PrimitiveMotion
  label?: string
  value?: string
  detail?: string
}) {
  return <article className={primitiveClass('primitive-mini-metric', color, motion)}>
    <span className="primitive-mini-metric-icon"><Activity size={16} /></span>
    <div><small>{label}</small><strong>{value}</strong><em>{detail}</em></div>
  </article>
}
