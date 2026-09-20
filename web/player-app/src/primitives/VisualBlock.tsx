export type BlockColor = 'white' | 'black' | 'gray' | 'blue' | 'green' | 'yellow' | 'red' | 'purple'
export type BlockMotion = 'static' | 'pulse' | 'fill-pulse'

export const BLOCK_COLORS: BlockColor[] = ['white', 'black', 'gray', 'blue', 'green', 'yellow', 'red', 'purple']
export const BLOCK_MOTIONS: BlockMotion[] = ['static', 'pulse', 'fill-pulse']

export function VisualBlock({
  color,
  motion = 'static',
  label,
}: {
  color: BlockColor
  motion?: BlockMotion
  label?: string
}) {
  return <div className={`primitive-block primitive-block-${color} primitive-block-motion-${motion}`}>
    <span>{label ?? 'block'}</span>
  </div>
}
