import { useState } from 'react'
import { ChevronDown, Info, Menu, Settings2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Checkbox } from '@/components/ui/checkbox'
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet'
import { Slider } from '@/components/ui/slider'
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip'

export function ShadcnCatalogSection({ number }: { number: string }) {
  const [checked, setChecked] = useState(true)
  const [open, setOpen] = useState(false)
  const [slider, setSlider] = useState([42])

  return <section className="catalog-section">
    <div className="catalog-section-title">
      <div><span>{number}</span><h2>shadcn/UI instalado</h2></div>
      <p>Componentes reais existentes em src/components/ui.</p>
    </div>

    <div className="shadcn-catalog-grid">
      <article className="shadcn-specimen" id="shadcn_button">
        <header><strong>button</strong><code>shadcn_button</code></header>
        <div className="shadcn-preview-row">
          <Button>Default</Button>
          <Button variant="outline">Outline</Button>
          <Button variant="secondary">Secondary</Button>
          <Button variant="ghost">Ghost</Button>
          <Button variant="destructive">Destructive</Button>
          <Button variant="link">Link</Button>
        </div>
      </article>

      <article className="shadcn-specimen" id="shadcn_checkbox">
        <header><strong>checkbox</strong><code>shadcn_checkbox</code></header>
        <label className="shadcn-inline-control"><Checkbox checked={checked} onCheckedChange={value => setChecked(value === true)} />Selecionado</label>
        <label className="shadcn-inline-control"><Checkbox disabled />Disabled</label>
      </article>

      <article className="shadcn-specimen" id="shadcn_collapsible">
        <header><strong>collapsible</strong><code>shadcn_collapsible</code></header>
        <Collapsible open={open} onOpenChange={setOpen}>
          <CollapsibleTrigger asChild><Button variant="outline">Abrir conteúdo <ChevronDown /></Button></CollapsibleTrigger>
          <CollapsibleContent className="shadcn-collapsible-content">Conteúdo expansível do componente.</CollapsibleContent>
        </Collapsible>
      </article>

      <article className="shadcn-specimen" id="shadcn_dropdown_menu">
        <header><strong>dropdown-menu</strong><code>shadcn_dropdown_menu</code></header>
        <DropdownMenu>
          <DropdownMenuTrigger asChild><Button variant="outline"><Menu />Abrir menu</Button></DropdownMenuTrigger>
          <DropdownMenuContent>
            <DropdownMenuItem><Settings2 />Configurações</DropdownMenuItem>
            <DropdownMenuItem><Info />Detalhes</DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem variant="destructive">Remover</DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </article>

      <article className="shadcn-specimen" id="shadcn_select">
        <header><strong>select</strong><code>shadcn_select</code></header>
        <Select defaultValue="radio">
          <SelectTrigger><SelectValue placeholder="Selecione" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="radio">Rádio</SelectItem>
            <SelectItem value="telephone">Telefone</SelectItem>
            <SelectItem value="sip">SIP</SelectItem>
          </SelectContent>
        </Select>
      </article>

      <article className="shadcn-specimen" id="shadcn_sheet">
        <header><strong>sheet</strong><code>shadcn_sheet</code></header>
        <Sheet>
          <SheetTrigger asChild><Button variant="outline">Abrir Sheet</Button></SheetTrigger>
          <SheetContent>
            <SheetHeader>
              <SheetTitle>Sheet de demonstração</SheetTitle>
              <SheetDescription>Exemplo real do componente instalado.</SheetDescription>
            </SheetHeader>
          </SheetContent>
        </Sheet>
      </article>

      <article className="shadcn-specimen" id="shadcn_slider">
        <header><strong>slider</strong><code>shadcn_slider</code></header>
        <div className="shadcn-slider-demo"><Slider value={slider} onValueChange={setSlider} max={100} step={1} /><strong>{slider[0]}%</strong></div>
      </article>

      <article className="shadcn-specimen" id="shadcn_tooltip">
        <header><strong>tooltip</strong><code>shadcn_tooltip</code></header>
        <TooltipProvider>
          <Tooltip>
            <TooltipTrigger asChild><Button variant="outline">Passe o mouse</Button></TooltipTrigger>
            <TooltipContent>Tooltip instalado e funcional</TooltipContent>
          </Tooltip>
        </TooltipProvider>
      </article>
    </div>
  </section>
}
