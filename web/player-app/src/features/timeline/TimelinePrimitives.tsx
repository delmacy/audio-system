import { Minus, Plus, Maximize2 } from 'lucide-react'

export function TimelineRuler() {
  return <div className="timeline-primitive-ruler">
    {[0,1,2,3,4].map(i => <div className="timeline-primitive-ruler-segment" key={i}>
      <span>{`00:0${i}:00`}</span>
      <i className="major" />
      <i /><i /><i /><i />
    </div>)}
  </div>
}

export function TimelinePlayhead() {
  return <div className="timeline-primitive-playhead-wrap">
    <div className="timeline-primitive-playhead-head" />
    <div className="timeline-primitive-playhead-line" />
  </div>
}

export function TimelineSelection() {
  return <div className="timeline-primitive-selection">
    <button type="button" aria-label="handle esquerdo" />
    <span>selection</span>
    <button type="button" aria-label="handle direito" />
  </div>
}

export function TimelineTrack() {
  return <div className="timeline-primitive-track">
    <div className="timeline-primitive-track-label">Rádio 01</div>
    <div className="timeline-primitive-track-lane">
      <div className="timeline-primitive-clip blue" style={{left:'7%',width:'26%'}} />
      <div className="timeline-primitive-clip purple" style={{left:'42%',width:'34%'}} />
    </div>
  </div>
}

export function TimelineNavigator() {
  return <div className="timeline-primitive-navigator">
    <div className="timeline-primitive-navigator-density">
      <span style={{left:'6%',width:'16%'}} />
      <span style={{left:'27%',width:'21%'}} />
      <span style={{left:'58%',width:'14%'}} />
      <span style={{left:'78%',width:'17%'}} />
    </div>
    <div className="timeline-primitive-navigator-window" style={{left:'32%',width:'28%'}}>
      <button type="button" className="left" aria-label="handle esquerdo" />
      <span>viewport</span>
      <button type="button" className="right" aria-label="handle direito" />
    </div>
  </div>
}

export function TimelineOverview() {
  return <div className="timeline-primitive-overview">
    <div className="timeline-primitive-overview-bars">
      {[18,42,24,68,33,54,20,72,48,31,60,26,75,40,52,22,66,35,58,28].map((h,i)=><i key={i} style={{height:`${h}%`}} />)}
    </div>
    <div className="timeline-primitive-overview-window" style={{left:'38%',width:'24%'}} />
  </div>
}

export function TimelineZoomControls() {
  return <div className="timeline-primitive-zoom">
    <button type="button" aria-label="zoom out"><Minus size={15}/></button>
    <input type="range" min="0" max="100" defaultValue="55" aria-label="zoom" />
    <button type="button" aria-label="zoom in"><Plus size={15}/></button>
    <button type="button" aria-label="fit all"><Maximize2 size={15}/>Fit</button>
  </div>
}
