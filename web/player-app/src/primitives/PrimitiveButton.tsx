import { AlertTriangle, Download, Pause, Play, Plus, Square, X } from 'lucide-react'

export type PrimitiveButtonColor = 'blue' | 'gray' | 'red' | 'green' | 'purple'
export type PrimitiveButtonVariant = 'solid' | 'outline' | 'ghost'
export type PrimitiveButtonSize = 'sm' | 'md' | 'lg'
export type PrimitiveButtonMotion = 'static' | 'pulse'
export type PrimitiveButtonIcon = 'plus' | 'x' | 'play' | 'pause' | 'square' | 'download' | 'alert_triangle'

const ICONS = {
  plus: Plus,
  x: X,
  play: Play,
  pause: Pause,
  square: Square,
  download: Download,
  alert_triangle: AlertTriangle,
} satisfies Record<PrimitiveButtonIcon, typeof Plus>

export function PrimitiveButton({
  color,
  variant = 'solid',
  size = 'md',
  motion = 'static',
  children,
  disabled = false,
  icon,
  iconOnly = false,
  ariaLabel,
}: {
  color: PrimitiveButtonColor
  variant?: PrimitiveButtonVariant
  size?: PrimitiveButtonSize
  motion?: PrimitiveButtonMotion
  children?: string
  disabled?: boolean
  icon?: PrimitiveButtonIcon
  iconOnly?: boolean
  ariaLabel?: string
}) {
  const Icon = icon ? ICONS[icon] : undefined

  return <button
    type="button"
    className={`primitive-button primitive-button-${color} primitive-button-${variant} primitive-button-${size} primitive-button-motion-${motion}${iconOnly ? ' primitive-button-icon' : ''}`}
    disabled={disabled}
    aria-label={ariaLabel}
  >
    {Icon && <Icon size={16} />}
    {!iconOnly && children}
  </button>
}
