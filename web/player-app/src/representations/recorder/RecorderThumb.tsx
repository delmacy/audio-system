import { Server, X } from 'lucide-react'
import { useState } from 'react'
import { RecorderFull } from './RecorderFull'
import type { SimStatus } from '@/features/simulator/model'

export function RecorderThumb({ status, displayName = 'Recorder' }: { status: SimStatus; displayName?: string }) {
  const [open, setOpen] = useState(false)

  return <>
    <button type="button" className="rep-recorder-thumb" onClick={() => setOpen(true)}>
      <span className="rep-thumb-icon"><Server size={22} /></span>
      <strong>{displayName}</strong>
      <small>10.10.0.10 · RTSP 8554</small>
      <span><i className="status-dot" />{status === 'running' ? 'Gravando' : 'Online'}</span>
    </button>

    {open && <div className="rep-modal-backdrop" role="presentation" onMouseDown={() => setOpen(false)}>
      <section className="rep-recorder-modal" role="dialog" aria-modal="true" aria-label={displayName} onMouseDown={event => event.stopPropagation()}>
        <header><div><span>Operação do gravador</span><strong>{displayName}</strong></div><button type="button" onClick={() => setOpen(false)} aria-label="Fechar"><X size={18} /></button></header>
        <RecorderFull mode="capture" status={status} displayName="RECORDER_full" />
      </section>
    </div>}
  </>
}
