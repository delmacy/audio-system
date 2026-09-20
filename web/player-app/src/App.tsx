import { TooltipProvider } from '@/components/ui/tooltip'
import { ComponentCatalogView } from '@/features/components/ComponentCatalogView'
import './App.css'

const CATALOG_EVENTS = [
  'Gravador pronto em 10.10.0.10',
  'Gateway SIP online em 10.10.0.20',
  'CWP-A01 conectado',
]

function App() {
  return <TooltipProvider>
    <ComponentCatalogView mode="simulation" status="stopped" events={CATALOG_EVENTS} />
  </TooltipProvider>
}

export default App
