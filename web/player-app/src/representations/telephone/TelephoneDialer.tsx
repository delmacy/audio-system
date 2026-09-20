import { Backspace, Phone, PhoneOff, X } from 'lucide-react'
import { useMemo, useState } from 'react'
import type { ServiceConfig } from '@/features/simulator/model'

const KEYS = ['1','2','3','4','5','6','7','8','9','*','0','#']

function extensionFromService(service: ServiceConfig) {
  const labelMatch = service.label.match(/(?:TEL(?:-SIM)?-)?(\d+)$/i)
  if (labelMatch) return labelMatch[1]
  const endpointMatch = service.endpoint.match(/(?:tel-|sim-[^-]+-t\d+@|sip:)([^@;:]+)/i)
  return endpointMatch?.[1] ?? service.label
}

export function TelephoneDialer({
  sourceLabel,
  telephones,
  initialNumber = '',
  onClose,
  onCall,
}: {
  sourceLabel: string
  telephones: ServiceConfig[]
  initialNumber?: string
  onClose?: () => void
  onCall?: (destination: ServiceConfig | null, dialedNumber: string) => void
}) {
  const [number, setNumber] = useState(initialNumber)
  const [calling, setCalling] = useState(false)

  const destinations = useMemo(
    () => telephones.map(telephone => ({ telephone, extension: extensionFromService(telephone) })),
    [telephones],
  )
  const matched = destinations.find(item => item.extension === number)?.telephone ?? null

  const call = () => {
    if (!number) return
    setCalling(true)
    onCall?.(matched, number)
  }

  return <section className="telephone-dialer" id="telephone_dialer">
    <header>
      <div>
        <span>Discador</span>
        <strong>{sourceLabel}</strong>
      </div>
      {onClose && <button type="button" onClick={onClose} aria-label="Fechar discador"><X size={17} /></button>}
    </header>

    <div className="telephone-dialer-display">
      <small>{calling ? 'CHAMANDO' : matched ? matched.label : 'DIGITE O RAMAL'}</small>
      <strong>{number || '—'}</strong>
      {matched && <span>{matched.endpoint}</span>}
    </div>

    <div className="telephone-dialer-keys">
      {KEYS.map(key => <button type="button" key={key} onClick={() => { setCalling(false); setNumber(current => current + key) }}>{key}</button>)}
    </div>

    <div className="telephone-dialer-actions">
      <button type="button" onClick={() => { setCalling(false); setNumber(current => current.slice(0,-1)) }} aria-label="Apagar último dígito"><Backspace size={17} /></button>
      <button type="button" className="call" onClick={call} disabled={!number}><Phone size={18} />Chamar</button>
      <button type="button" className="hangup" onClick={() => setCalling(false)} disabled={!calling}><PhoneOff size={18} /></button>
    </div>

    <div className="telephone-dialer-directory">
      <span>Ramais cadastrados</span>
      <div>
        {destinations.map(({ telephone, extension }) => <button type="button" key={telephone.id} onClick={() => { setCalling(false); setNumber(extension) }}>
          <strong>{extension}</strong><small>{telephone.label}</small>
        </button>)}
      </div>
    </div>
  </section>
}
