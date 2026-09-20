import { Activity } from 'lucide-react'

export function SummaryCard({ icon: Icon, title, value, detail, tone = 'blue' }: {
  icon: typeof Activity
  title: string
  value: string
  detail: string
  tone?: 'blue' | 'green' | 'orange' | 'red'
}) {
  return <article className={`sim-summary-card ${tone}`}>
    <div className="sim-summary-icon"><Icon size={25} strokeWidth={1.9} /></div>
    <div><span>{title}</span><strong>{value}</strong><small>{detail}</small></div>
    <i className="status-dot" />
  </article>
}
