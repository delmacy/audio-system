import {
  TimelineNavigator,
  TimelineOverview,
  TimelinePlayhead,
  TimelineRuler,
  TimelineSelection,
  TimelineTrack,
  TimelineZoomControls,
} from '@/features/timeline/TimelinePrimitives'
import { TimelineRulerZoom } from '@/features/timeline/TimelineRulerZoom'
import { TimelineDataLab } from '@/features/timeline/TimelineDataLab'
import { RecordedTrackLab } from '@/features/timeline/RecordedTrackLab'

function Specimen({ id, children }: { id: string; children: React.ReactNode }) {
  return <article className="primitive-specimen timeline-specimen" id={id}>
    <div className="primitive-specimen-preview">{children}</div>
    <code>{id}</code>
  </article>
}

export function TimelineCatalogSection({ number }: { number: string }) {
  return <section className="catalog-section">
    <div className="catalog-section-title">
      <div><span>{number}</span><h2>Timeline</h2></div>
      <p>Primitivos temporais inspirados em editores multitrack.</p>
    </div>

    <div className="timeline-catalog-stack">
      <section className="primitive-family">
        <header><strong>recorded tracks</strong><small>material persistido por trilha + checkbox de futura escuta</small></header>
        <RecordedTrackLab />
      </section>

      <section className="primitive-family">
        <header><strong>data lab</strong><small>fixture/real + recebimento + DTO + contagem renderizável</small></header>
        <TimelineDataLab />
      </section>
      <section className="primitive-family">
        <header><strong>ruler</strong><small>régua temporal e subdivisões</small></header>
        <div className="timeline-catalog-grid">
          <Specimen id="timeline_ruler"><TimelineRuler /></Specimen>
        </div>
      </section>

      <section className="primitive-family">
        <header><strong>ruler + zoom</strong><small>componente funcional com escala temporal dinâmica</small></header>
        <div className="timeline-catalog-grid single">
          <Specimen id="timeline_ruler_zoom"><TimelineRulerZoom durationSeconds={8 * 60 * 60} /></Specimen>
        </div>
      </section>

      <section className="primitive-family">
        <header><strong>track + clip</strong><small>trilha lógica e segmentos temporais sem waveform</small></header>
        <div className="timeline-catalog-grid">
          <Specimen id="timeline_track"><TimelineTrack /></Specimen>
          <Specimen id="timeline_clip_blue"><div className="timeline-primitive-clip standalone blue" /></Specimen>
          <Specimen id="timeline_clip_purple"><div className="timeline-primitive-clip standalone purple" /></Specimen>
        </div>
      </section>

      <section className="primitive-family">
        <header><strong>cursor + selection</strong><small>playhead e intervalo selecionado</small></header>
        <div className="timeline-catalog-grid">
          <Specimen id="timeline_playhead"><div className="timeline-demo-height"><TimelinePlayhead /></div></Specimen>
          <Specimen id="timeline_selection"><TimelineSelection /></Specimen>
        </div>
      </section>

      <section className="primitive-family">
        <header><strong>navigation</strong><small>pan, viewport, handles e visão geral</small></header>
        <div className="timeline-catalog-grid">
          <Specimen id="timeline_navigator"><TimelineNavigator /></Specimen>
          <Specimen id="timeline_overview"><TimelineOverview /></Specimen>
          <Specimen id="timeline_zoom_controls"><TimelineZoomControls /></Specimen>
        </div>
      </section>
    </div>
  </section>
}
