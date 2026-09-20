export type PrimitiveColor = 'green' | 'yellow' | 'red' | 'gray'
export type PrimitiveMotion = 'static' | 'pulse' | 'blink' | 'ping'

export const PRIMITIVE_COLORS: PrimitiveColor[] = ['green', 'yellow', 'red', 'gray']
export const PRIMITIVE_MOTIONS: PrimitiveMotion[] = ['static', 'pulse', 'blink', 'ping']

export function primitiveClass(base: string, color: PrimitiveColor, motion: PrimitiveMotion) {
  return `${base} primitive-color-${color} primitive-motion-${motion}`
}

export function primitiveId(prefix: string, color: PrimitiveColor, motion: PrimitiveMotion) {
  return motion === 'static' ? `${prefix}_${color}` : `${prefix}_${color}_${motion}`
}
