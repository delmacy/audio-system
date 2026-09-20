import { create } from 'zustand'
import { TOTAL_MINUTES, clampMinute, type TimelineGroup } from './timeline-model'

type Panel = 'settings' | 'export' | 'filters' | 'session' | 'preferences' | null
type PlaybackMode = 'continuous' | 'only-audio' | 'only-activity'

type TimelineState = {
  groups: TimelineGroup[]
  expanded: string[]
  selectedTracks: string[]
  selectionStart: number
  selectionEnd: number
  playhead: number
  zoom: number
  playing: boolean
  sidebarCollapsed: boolean
  panel: Panel
  playbackMode: PlaybackMode
  setGroups: (groups: TimelineGroup[]) => void
  toggleGroup: (id: string) => void
  toggleTrack: (id: string) => void
  setGroupSelected: (id: string, checked: boolean) => void
  setSelection: (start: number, end: number) => void
  setPlayhead: (minute: number) => void
  setZoom: (value: number) => void
  setPlaying: (value: boolean) => void
  setSidebarCollapsed: (value: boolean) => void
  setPanel: (value: Panel) => void
  setPlaybackMode: (value: PlaybackMode) => void
  tick: (elapsedMinutes: number) => void
}

export const useTimelineStore = create<TimelineState>((set) => ({
  groups: [],
  expanded: [],
  selectedTracks: [],
  selectionStart: 0,
  selectionEnd: TOTAL_MINUTES,
  playhead: 0,
  zoom: 1,
  playing: false,
  sidebarCollapsed: false,
  panel: null,
  playbackMode: 'continuous',
  setGroups: groups => set(state => ({
    groups,
    expanded: groups.map(group => group.id),
    selectedTracks: groups.flatMap(group => group.tracks.map(track => track.id)),
    selectionStart: state.selectionStart,
    selectionEnd: state.selectionEnd,
    playing: false,
  })),
  toggleGroup: id => set(state => ({
    expanded: state.expanded.includes(id) ? state.expanded.filter(item => item !== id) : [...state.expanded, id],
  })),
  toggleTrack: id => set(state => ({
    selectedTracks: state.selectedTracks.includes(id)
      ? state.selectedTracks.filter(item => item !== id)
      : [...state.selectedTracks, id],
  })),
  setGroupSelected: (id, checked) => set(state => {
    const ids = state.groups.find(group => group.id === id)?.tracks.map(track => track.id) ?? []
    return { selectedTracks: checked
      ? Array.from(new Set([...state.selectedTracks, ...ids]))
      : state.selectedTracks.filter(item => !ids.includes(item)) }
  }),
  setSelection: (start, end) => set(() => {
    const boundedStart = Math.min(TOTAL_MINUTES - 0.25, clampMinute(Math.min(start, end)))
    const boundedEnd = Math.max(boundedStart + 0.25, clampMinute(Math.max(start, end)))
    return { selectionStart: boundedStart, selectionEnd: boundedEnd }
  }),
  setPlayhead: playhead => set({ playhead: clampMinute(playhead) }),
  setZoom: zoom => set({ zoom: Math.max(1, Math.min(4, zoom)) }),
  setPlaying: playing => set({ playing }),
  setSidebarCollapsed: sidebarCollapsed => set({ sidebarCollapsed }),
  setPanel: panel => set({ panel }),
  setPlaybackMode: playbackMode => set({ playbackMode }),
  tick: elapsedMinutes => set(state => {
    if (!state.playing) return state
    const next = state.playhead + elapsedMinutes
    return next >= Math.min(state.selectionEnd, TOTAL_MINUTES)
      ? { playhead: state.selectionEnd, playing: false }
      : { playhead: next }
  }),
}))
