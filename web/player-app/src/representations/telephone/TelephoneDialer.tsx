import { Phone, PhoneOff, X } from 'lucide-react'
import { useState } from 'react'
import type { ServiceConfig } from '@/features/simulator/model'

function extensionOf(service: ServiceConfig) {
  const match = service.label.match(/(\d+)$/)
  return match?.[1] ?? service.label
}

export function TelephoneDialer({
  source,
  telephones,
  onClose,
}: {
  source?: ServiceConfig
  telephones: ServiceConfig[]
  onClose?: () => void
}) {
  const [number, setNumber] = useState('')
  const [calling, setCalling] = useState(false)
  const destinations = source ? telephones.filter(item => item.id !== source.id) : telephones
  const matched = destinations.find(item => extensionOf(item) === number)

  const append = (digit: string) => {
    setCalling(false)
    setNumber(current => current + digit)
  }

  return <section className="telephone-dialer" id="telephone_dialer">
    <header>
      <div>
        <span>Discador</span>
        <strong>{source ? source.label : 'Telefone'}</strong>
      </div>
      {onClose && <button type="button" onClick={onClose} aria-label="Fechar discador"><X size={17} /></button>}
    </header>

    <div className="telephone-dialer-display">
      <small>{calling ? 'CHAMANDO' : matched ? matched.label : 'DIGITE O RAMAL'}</small>
      <strong>{number || '—'}</strong>
      {matched && <span>{matched.endpoint}</span>}
    </div>

    <div className="telephone-dialer-keys">
      {['1','2','3','4','5','6','7','8','9','*','0','#'].map(key =>
        <button type="button" key={key} onClick={() => append(key)}>{key}</button>
      )}
    </div>

    <div className="telephone-dialer-actions">
      <button type="button" onClick={() => { setCalling(false); setNumber(current => current.slice(0, -1)) }} aria-label="Apagar último dígito">⌫</button>
      <button type="button" className="call" onClick={() => number && setCalling(true)} disabled={!number}>
        <Phone size={17} />Chamar
      </button>
      <button type="button" className="hangup" onClick={() => setCalling(false)} disabled={!calling} aria-label="Encerrar chamada">
        <PhoneOff size={17} />
      </button>
    </div>

    <div className="telephone-dialer-directory">
      <span>Ramais cadastrados</span>
      <div>
        {destinations.map(telephone => {
          const extension = extensionOf(telephone)
          return <button type="button" key={telephone.id} onClick={() => { setCalling(false); setNumber(extension) }}>
            <strong>{extension}</strong>
            <small>{telephone.label}</small>
          </button>
        })}
      </div>
    </div>
  </section>
}
