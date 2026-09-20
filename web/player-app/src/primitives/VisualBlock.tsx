export type BlockColor = 'blue' | 'gray' | 'red' | 'green' | 'yellow' | 'purple'
export type BlockFill = 'white' | 'blue' | 'gray' | 'red' | 'green' | 'yellow' | 'purple'
export type BlockMotion = 'static' | 'pulse'

export const BLOCK_COLORS: BlockColor[] = ['blue', 'gray', 'red', 'green', 'yellow', 'purple']
export const BLOCK_FILLS: BlockFill[] = ['white', 'blue', 'gray', 'red', 'green', 'yellow', 'purple']

export function VisualBlock({
  borderColor,
  fillColor,
  motion = 'static',
  label,
}: {
  borderColor: BlockColor
  fillColor: BlockFill
  motion?: BlockMotion
  label?: string
}) {
  return <div className={`primitive-block primitive-block-border-${borderColor} primitive-block-fill-${fillColor} primitive-block-motion-${motion}`}>
    <span>{label ?? 'block'}</span>
  </div>
}
