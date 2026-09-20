import { useState } from 'react'
import { ChevronDown, Info, Menu, Settings2 } from 'lucide-react'
import { Collapsible } from '@/components/ui/collapsible'
import {
  DropdownMenu,
  DropdownMenuItem,
  DropdownMenuSeparator,
} from '@/components/ui/dropdown-menu'
import {
  Select,
  SelectItem,
  SelectValue,
} from '@/components/ui/select'
import {
  Sheet,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet'
import { Tooltip, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip'
import {
  THEMED_UI_COLORS,
  ThemedButton,
  ThemedCheckbox,
  ThemedCollapsibleContent,
  ThemedCollapsibleTrigger,
  ThemedDropdownMenuContent,
  ThemedDropdownMenuTrigger,
  ThemedSelectContent,
  ThemedSelectTrigger,
  ThemedSheetContent,
  ThemedSlider,
  ThemedTooltipContent,
  type ThemedUiColor,
} from '@/components/themed-ui'

function VariantGrid({ render }: { render: (color: ThemedUiColor, pulse: boolean) => React.ReactNode }) {
  return <div className="themed-ui-variant-grid">
    {THEMED_UI_COLORS.flatMap(color => [false, true].map(pulse => {
      const id = `${color}_${pulse ? 'pulse' : 'static'}`
      return <div className="themed-ui-variant" key={id}>
        {render(color, pulse)}
        <code>{id}</code>
      </div>
    }))}
  </div>
}

export function ShadcnCatalogSection({ number }: { number: string }) {
  const [checked, setChecked] = useState(true)
  const [open, setOpen] = useState(false)
  const [slider, setSlider] = useState([42])

  return <section className="catalog-section">
    <div className="catalog-section-title">
      <div><span>{number}</span><h2>shadcn/UI · adaptado ao tema</h2></div>
      <p>Wrappers prontos para uso: blue · gray · red · green · purple × static · pulse.</p>
    </div>

    <div className="shadcn-theme-stack">
      <article className="shadcn-specimen">
        <header><strong>button</strong><code>themed_button</code></header>
        <VariantGrid render={(color, pulse) => <ThemedButton color={color} motion={pulse ? 'pulse' : 'static'}>{`button_${color}`}</ThemedButton>} />
      </article>

      <article className="shadcn-specimen">
        <header><strong>checkbox</strong><code>themed_checkbox</code></header>
        <VariantGrid render={(color, pulse) => <label className="shadcn-inline-control"><ThemedCheckbox color={color} motion={pulse ? 'pulse' : 'static'} checked={checked} onCheckedChange={value => setChecked(value === true)} />{color}</label>} />
      </article>

      <article className="shadcn-specimen">
        <header><strong>slider</strong><code>themed_slider</code></header>
        <VariantGrid render={(color, pulse) => <div className="themed-slider-cell"><ThemedSlider color={color} motion={pulse ? 'pulse' : 'static'} value={slider} onValueChange={setSlider} max={100} step={1} /><span>{slider[0]}%</span></div>} />
      </article>

      <article className="shadcn-specimen">
        <header><strong>select</strong><code>themed_select</code></header>
        <VariantGrid render={(color, pulse) => <Select defaultValue="radio">
          <ThemedSelectTrigger color={color} motion={pulse ? 'pulse' : 'static'}><SelectValue /></ThemedSelectTrigger>
          <ThemedSelectContent color={color}>
            <SelectItem value="radio">Rádio</SelectItem>
            <SelectItem value="telephone">Telefone</SelectItem>
            <SelectItem value="sip">SIP</SelectItem>
          </ThemedSelectContent>
        </Select>} />
      </article>

      <article className="shadcn-specimen">
        <header><strong>dropdown-menu</strong><code>themed_dropdown_menu</code></header>
        <VariantGrid render={(color, pulse) => <DropdownMenu>
          <ThemedDropdownMenuTrigger asChild color={color} motion={pulse ? 'pulse' : 'static'}>
            <ThemedButton color={color} variant="outline"><Menu />Menu</ThemedButton>
          </ThemedDropdownMenuTrigger>
          <ThemedDropdownMenuContent color={color}>
            <DropdownMenuItem><Settings2 />Configurações</DropdownMenuItem>
            <DropdownMenuItem><Info />Detalhes</DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem variant="destructive">Remover</DropdownMenuItem>
          </ThemedDropdownMenuContent>
        </DropdownMenu>} />
      </article>

      <article className="shadcn-specimen">
        <header><strong>collapsible</strong><code>themed_collapsible</code></header>
        <Collapsible open={open} onOpenChange={setOpen}>
          <VariantGrid render={(color, pulse) => <div>
            <ThemedCollapsibleTrigger asChild color={color} motion={pulse ? 'pulse' : 'static'}>
              <ThemedButton color={color} variant="outline">Abrir <ChevronDown /></ThemedButton>
            </ThemedCollapsibleTrigger>
            <ThemedCollapsibleContent color={color}>Conteúdo expansível temático.</ThemedCollapsibleContent>
          </div>} />
        </Collapsible>
      </article>

      <article className="shadcn-specimen">
        <header><strong>sheet</strong><code>themed_sheet</code></header>
        <div className="shadcn-preview-row">
          {THEMED_UI_COLORS.map(color => <Sheet key={color}>
            <SheetTrigger asChild><ThemedButton color={color} variant="outline">Sheet {color}</ThemedButton></SheetTrigger>
            <ThemedSheetContent color={color}>
              <SheetHeader><SheetTitle>Sheet {color}</SheetTitle><SheetDescription>Conteúdo adaptado ao tema.</SheetDescription></SheetHeader>
            </ThemedSheetContent>
          </Sheet>)}
        </div>
      </article>

      <article className="shadcn-specimen">
        <header><strong>tooltip</strong><code>themed_tooltip</code></header>
        <TooltipProvider>
          <div className="shadcn-preview-row">
            {THEMED_UI_COLORS.map(color => <Tooltip key={color}>
              <TooltipTrigger asChild><ThemedButton color={color} variant="ghost">Tooltip {color}</ThemedButton></TooltipTrigger>
              <ThemedTooltipContent color={color}>Tooltip {color}</ThemedTooltipContent>
            </Tooltip>)}
          </div>
        </TooltipProvider>
      </article>
    </div>
  </section>
}
