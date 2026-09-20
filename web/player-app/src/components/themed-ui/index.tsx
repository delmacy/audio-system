import type * as React from 'react'
import { Button } from '@/components/ui/button'
import { Checkbox } from '@/components/ui/checkbox'
import { CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible'
import { DropdownMenuContent, DropdownMenuTrigger } from '@/components/ui/dropdown-menu'
import { SelectContent, SelectTrigger } from '@/components/ui/select'
import { SheetContent } from '@/components/ui/sheet'
import { Slider } from '@/components/ui/slider'
import { TooltipContent } from '@/components/ui/tooltip'

export type ThemedUiColor = 'blue' | 'gray' | 'red' | 'green' | 'purple'
export type ThemedUiMotion = 'static' | 'pulse'

function themedClass(base: string, color: ThemedUiColor, motion: ThemedUiMotion, className?: string) {
  return [base, `themed-ui-${color}`, `themed-ui-motion-${motion}`, className].filter(Boolean).join(' ')
}

export function ThemedButton({
  color = 'blue',
  motion = 'static',
  className,
  ...props
}: React.ComponentProps<typeof Button> & { color?: ThemedUiColor; motion?: ThemedUiMotion }) {
  return <Button className={themedClass('themed-ui-button', color, motion, className)} {...props} />
}

export function ThemedCheckbox({
  color = 'blue',
  motion = 'static',
  className,
  ...props
}: React.ComponentProps<typeof Checkbox> & { color?: ThemedUiColor; motion?: ThemedUiMotion }) {
  return <Checkbox className={themedClass('themed-ui-checkbox', color, motion, className)} {...props} />
}

export function ThemedSlider({
  color = 'blue',
  motion = 'static',
  className,
  ...props
}: React.ComponentProps<typeof Slider> & { color?: ThemedUiColor; motion?: ThemedUiMotion }) {
  return <Slider className={themedClass('themed-ui-slider', color, motion, className)} {...props} />
}

export function ThemedSelectTrigger({
  color = 'blue',
  motion = 'static',
  className,
  ...props
}: React.ComponentProps<typeof SelectTrigger> & { color?: ThemedUiColor; motion?: ThemedUiMotion }) {
  return <SelectTrigger className={themedClass('themed-ui-select-trigger', color, motion, className)} {...props} />
}

export function ThemedSelectContent({
  color = 'blue',
  className,
  ...props
}: React.ComponentProps<typeof SelectContent> & { color?: ThemedUiColor }) {
  return <SelectContent className={themedClass('themed-ui-select-content', color, 'static', className)} {...props} />
}

export function ThemedDropdownMenuTrigger({
  color = 'blue',
  motion = 'static',
  className,
  ...props
}: React.ComponentProps<typeof DropdownMenuTrigger> & { color?: ThemedUiColor; motion?: ThemedUiMotion }) {
  return <DropdownMenuTrigger className={themedClass('themed-ui-menu-trigger', color, motion, className)} {...props} />
}

export function ThemedDropdownMenuContent({
  color = 'blue',
  className,
  ...props
}: React.ComponentProps<typeof DropdownMenuContent> & { color?: ThemedUiColor }) {
  return <DropdownMenuContent className={themedClass('themed-ui-menu-content', color, 'static', className)} {...props} />
}

export function ThemedSheetContent({
  color = 'blue',
  className,
  ...props
}: React.ComponentProps<typeof SheetContent> & { color?: ThemedUiColor }) {
  return <SheetContent className={themedClass('themed-ui-sheet-content', color, 'static', className)} {...props} />
}

export function ThemedTooltipContent({
  color = 'blue',
  className,
  ...props
}: React.ComponentProps<typeof TooltipContent> & { color?: ThemedUiColor }) {
  return <TooltipContent className={themedClass('themed-ui-tooltip-content', color, 'static', className)} {...props} />
}

export function ThemedCollapsibleTrigger({
  color = 'blue',
  motion = 'static',
  className,
  ...props
}: React.ComponentProps<typeof CollapsibleTrigger> & { color?: ThemedUiColor; motion?: ThemedUiMotion }) {
  return <CollapsibleTrigger className={themedClass('themed-ui-collapsible-trigger', color, motion, className)} {...props} />
}

export function ThemedCollapsibleContent({
  color = 'blue',
  className,
  ...props
}: React.ComponentProps<typeof CollapsibleContent> & { color?: ThemedUiColor }) {
  return <CollapsibleContent className={themedClass('themed-ui-collapsible-content', color, 'static', className)} {...props} />
}

export const THEMED_UI_COLORS: ThemedUiColor[] = ['blue', 'gray', 'red', 'green', 'purple']
