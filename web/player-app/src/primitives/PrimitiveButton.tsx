import { Plus } from 'lucide-react'

export type PrimitiveButtonColor = 'blue' | 'gray' | 'red' | 'green'
export type PrimitiveButtonVariant = 'solid' | 'outline' | 'ghost'
export type PrimitiveButtonSize = 'sm' | 'md' | 'lg'

export function PrimitiveButton({
  color,
  variant = 'solid',
  size = 'md',
  children,
  disabled = false,
  iconOnly = false,
  ariaLabel,
}: {
  color: PrimitiveButtonColor
  variant?: PrimitiveButtonVariant
  size?: PrimitiveButtonSize
  children?: string
  disabled?: boolean
  iconOnly?: boolean
  ariaLabel?: string
}) {
  return <button
    type="button"
    className={`primitive-button primitive-button-${color} primitive-button-${variant} primitive-button-${size}${iconOnly ? ' primitive-button-icon' : ''}`}
    disabled={disabled}
    aria-label={ariaLabel}
  >
    {iconOnly ? <Plus size={16} /> : children}
  </button>
}
