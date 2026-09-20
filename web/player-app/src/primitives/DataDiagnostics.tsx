export type DataSourceState = 'connected' | 'loading' | 'empty' | 'stale' | 'error'

const STATE_LABEL: Record<DataSourceState, string> = {
  connected: 'connected',
  loading: 'loading',
  empty: 'empty',
  stale: 'stale',
  error: 'error',
}

export function DataSourceStatus({
  state,
  source,
  detail,
  updatedAt,
}: {
  state: DataSourceState
  source: string
  detail?: string
  updatedAt?: string | null
}) {
  return <div className={`data-source-status data-source-status-${state}`}>
    <span className="data-source-status-dot" aria-hidden="true" />
    <div>
      <strong>{source}</strong>
      <small>{STATE_LABEL[state]}{detail ? ` · ${detail}` : ''}</small>
    </div>
    {updatedAt && <time>{updatedAt}</time>}
  </div>
}

export function DataProbe({
  rawCount,
  dtoCount,
  renderedCount,
  discardedCount = 0,
}: {
  rawCount: number
  dtoCount: number
  renderedCount: number
  discardedCount?: number
}) {
  return <div className="data-probe">
    <div><span>RAW</span><strong>{rawCount}</strong></div>
    <i>→</i>
    <div><span>DTO</span><strong>{dtoCount}</strong></div>
    <i>→</i>
    <div><span>UI</span><strong>{renderedCount}</strong></div>
    <div className={`data-probe-discarded ${discardedCount > 0 ? 'has-discarded' : ''}`}>
      <span>discarded</span><strong>{discardedCount}</strong>
    </div>
  </div>
}
